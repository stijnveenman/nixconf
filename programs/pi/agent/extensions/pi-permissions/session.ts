import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CONFIG_DIR_NAME, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { clearProjectApprovals, loadProjectApprovals, saveProjectApprovals } from "./approvals.ts";
import { type Check, checksFor } from "./checks.ts";
import { type LoadedConfig, loadConfig } from "./config.ts";
import { promptQueue, showPrompt } from "./prompt.ts";
import { type AskAnswer, type PermissionNode, prompterFor, registry, rootOf } from "./registry.ts";
import { type Decision, decide, isFullyDenied, normalizeAction, type Resource, type Rule } from "./rules.ts";

export const TAG = "[pi-permissions]";
const ROOT_AGENT = "main";

type Block = { block: true; reason: string };

/** This extension's state for one pi session: its node in the session tree and its rules. */
export class PermissionSession {
  readonly agentDir = getAgentDir();
  node: PermissionNode | undefined;
  private ui: ExtensionContext["ui"] | undefined;
  private config: LoadedConfig | undefined;
  private reportedErrors = "";
  private readonly prompt = promptQueue((request) =>
    this.ui ? showPrompt(this.ui, request) : Promise.resolve<AskAnswer>({ kind: "deny", reason: "no interactive UI is available" }),
  );

  get sessionId(): string | undefined {
    return this.node?.sessionId;
  }

  get agentName(): string | undefined {
    return this.node?.agentName ?? (this.node?.parentId ? undefined : ROOT_AGENT);
  }

  get configErrors(): string[] {
    return this.config?.errors ?? [];
  }

  private get who(): string {
    return this.node?.parentId ? `subagent ${this.node.agentName ?? "(unknown agent)"}` : "pi";
  }

  register(ctx: ExtensionContext): PermissionNode {
    if (ctx.hasUI) this.ui = ctx.ui;
    const sessionId = ctx.sessionManager.getSessionId();
    if (this.node?.sessionId === sessionId) return this.node;
    const { nodes, children } = registry();
    if (this.node) nodes.delete(this.node.sessionId);
    const announced = children.get(sessionId);
    const parentFromEnv = process.env.PI_SUBAGENT_PARENT_SESSION;
    this.node = {
      sessionId,
      parentId: announced?.parentId ?? (parentFromEnv !== sessionId ? parentFromEnv : undefined),
      agentName: announced?.agentName,
      sessionApprovals: [],
      prompt: ctx.hasUI ? this.prompt : undefined,
    };
    nodes.set(sessionId, this.node);
    return this.node;
  }

  unregister(): void {
    if (this.node) registry().nodes.delete(this.node.sessionId);
    this.node = undefined;
    this.ui = undefined;
  }

  reload(ctx: ExtensionContext): void {
    const paths = { agentDir: this.agentDir, configDirName: CONFIG_DIR_NAME, cwd: ctx.cwd, trusted: ctx.isProjectTrusted() };
    this.config = loadConfig(paths, (content) => parseFrontmatter(content));
    const errors = this.config.errors.join("\n");
    if (errors && errors !== this.reportedErrors && ctx.hasUI) ctx.ui.notify(`${TAG} config errors:\n${errors}`, "warning");
    this.reportedErrors = errors;
  }

  rules(ctx: ExtensionContext): Rule[] {
    if (!this.config) this.reload(ctx);
    return this.config!.rulesFor(this.agentName);
  }

  approvals(ctx: ExtensionContext): Rule[] {
    const session = this.node ? rootOf(this.node).sessionApprovals : [];
    return [...session, ...loadProjectApprovals(this.agentDir, ctx.cwd)];
  }

  clearApprovals(ctx: ExtensionContext): { session: number; saved: number } {
    const root = this.node ? rootOf(this.node) : undefined;
    const session = root?.sessionApprovals.length ?? 0;
    if (root) root.sessionApprovals = [];
    return { session, saved: clearProjectApprovals(this.agentDir, ctx.cwd) };
  }

  /** Tools whose action every rule denies, so the model is not offered them. */
  hideDeniedTools(ctx: ExtensionContext, selectedTools: string[]): void {
    const rules = this.rules(ctx);
    const keep = selectedTools.filter((tool) => !isFullyDenied(rules, normalizeAction(tool)));
    selectedTools.splice(0, selectedTools.length, ...keep);
  }

  async checkToolCall(toolName: string, input: Record<string, unknown>, ctx: ExtensionContext): Promise<Block | undefined> {
    for (const check of checksFor(toolName, input, ctx.cwd)) {
      const block = await this.enforce(check, ctx);
      if (block) return block;
    }
    return undefined;
  }

  private decide(check: Check, ctx: ExtensionContext): Decision {
    return decide(check.action, check.resources, this.rules(ctx), this.approvals(ctx));
  }

  private async enforce(check: Check, ctx: ExtensionContext): Promise<Block | undefined> {
    const decision = this.decide(check, ctx);
    if (decision.effect === "allow") return undefined;
    if (decision.effect === "deny") return this.denied(check, decision);

    const prompter = this.node && prompterFor(this.node);
    const lines = decision.resources.map(describe);
    if (!prompter?.prompt) {
      return block(`${check.action} ${lines.join(", ")} needs approval, but no interactive UI is available to ask. Ask the user to allow it in permissions.json.`);
    }
    const patterns = decision.resources.map((resource) => check.patterns[check.resources.indexOf(resource)] ?? "*");
    const answer = await prompter.prompt({
      who: this.who,
      action: check.action,
      lines,
      patterns,
      stillNeeded: () => this.decide(check, ctx).effect !== "allow",
    });
    if (answer.kind === "deny") {
      const why = answer.reason ? `: ${answer.reason}` : answer.feedback ? `. User feedback: ${answer.feedback}` : "";
      return block(`The user denied ${check.action} ${lines.join(", ")}${why}`);
    }
    this.remember(answer.kind, check.action, patterns, ctx);
    return undefined;
  }

  private denied(check: Check, decision: Decision): Block {
    const rule = decision.rule;
    const from = rule?.source ? ` (rule ${rule.action} ${rule.resource} → deny, from ${rule.source})` : "";
    const value = quote(decision.resources[0].value);
    return block(`${check.action} ${value} is denied for ${this.who}${from}. Do not try to work around this; ask the user if it is needed.`);
  }

  private remember(kind: "once" | "session" | "project", action: string, patterns: string[], ctx: ExtensionContext): void {
    if (kind === "once") return;
    const source = kind === "project" ? "saved approval" : "session approval";
    const rules = [...new Set(patterns)].map<Rule>((resource) => ({ action, resource, effect: "allow", source }));
    if (kind === "project") saveProjectApprovals(this.agentDir, ctx.cwd, rules);
    else if (this.node) rootOf(this.node).sessionApprovals.push(...rules);
  }
}

function block(reason: string): Block {
  return { block: true, reason: `${TAG} ${reason}` };
}

function quote(value: string): string {
  return `\`${value.length > 200 ? `${value.slice(0, 200)}…` : value}\``;
}

function describe(resource: Resource): string {
  return resource.opaque ? `${quote(resource.value)} (${resource.reason ?? "cannot see what it runs"})` : quote(resource.value);
}
