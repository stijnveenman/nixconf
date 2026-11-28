/**
 * pi-permissions: opencode v2-style permissions for pi.
 *
 * Every tool call is checked against an ordered list of
 * `{ action, resource, effect }` rules (last match wins, no match asks). Rules
 * come from opencode's defaults, `~/.pi/agent/permissions.json`, a trusted
 * project's `.pi/permissions.json`, then per-agent rules (`agents.<name>` in
 * those files and `permission:`/`permissions:` in the agent's frontmatter).
 *
 * Works with @gotgenes/pi-subagents: each subagent is judged by its own agent's
 * rules, the `subagent` action controls which agents may be launched, and a
 * subagent's asks are shown in the parent session's UI. See README.md.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CONFIG_DIR_NAME, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { checksFor } from "./checks.ts";
import {
  clearProjectApprovals,
  type LoadedConfig,
  loadConfig,
  loadProjectApprovals,
  saveProjectApprovals,
} from "./config.ts";
import { type AskAnswer, type AskRequest, type PermissionNode, prompterFor, registry, rootOf } from "./registry.ts";
import { decide, isFullyDenied, normalizeAction, type Resource, type Rule } from "./rules.ts";

const ROOT_AGENT = "main";
const TAG = "[pi-permissions]";

export default function piPermissions(pi: ExtensionAPI) {
  const agentDir = getAgentDir();
  let node: PermissionNode | undefined;
  let uiCtx: ExtensionContext | undefined;
  let config: LoadedConfig | undefined;
  let reportedErrors = "";
  let promptChain: Promise<unknown> = Promise.resolve();

  const reload = (ctx: ExtensionContext) => {
    config = loadConfig(
      { agentDir, configDirName: CONFIG_DIR_NAME, cwd: ctx.cwd, trusted: ctx.isProjectTrusted() },
      (content) => parseFrontmatter(content),
    );
    const errors = config.errors.join("\n");
    if (errors && errors !== reportedErrors && ctx.hasUI) ctx.ui.notify(`${TAG} config errors:\n${errors}`, "warning");
    reportedErrors = errors;
  };

  const agentName = () => node?.agentName ?? (node?.parentId ? undefined : ROOT_AGENT);
  const rules = (ctx: ExtensionContext): Rule[] => {
    if (!config) reload(ctx);
    return config!.rulesFor(agentName());
  };
  const approvals = (ctx: ExtensionContext): Rule[] => [
    ...(node ? rootOf(node).sessionApprovals : []),
    ...loadProjectApprovals(agentDir, ctx.cwd),
  ];
  const who = () => (node?.parentId ? `subagent ${node.agentName ?? "(unknown agent)"}` : "pi");

  // ── Node registration ───────────────────────────────────────────────────

  const register = (ctx: ExtensionContext) => {
    const sessionId = ctx.sessionManager.getSessionId();
    const reg = registry();
    if (node?.sessionId === sessionId) return node;
    if (node) reg.nodes.delete(node.sessionId);
    const child = reg.children.get(sessionId);
    const parentEnv = process.env.PI_SUBAGENT_PARENT_SESSION;
    node = {
      sessionId,
      parentId: child?.parentId ?? (parentEnv && parentEnv !== sessionId ? parentEnv : undefined),
      agentName: child?.agentName,
      sessionApprovals: [],
    };
    if (ctx.hasUI) {
      uiCtx = ctx;
      node.prompt = (request) => {
        const next = promptChain.then(() => (request.stillNeeded() ? showPrompt(request) : ({ kind: "once" } as AskAnswer)));
        promptChain = next.catch(() => undefined);
        return next;
      };
    }
    reg.nodes.set(sessionId, node);
    return node;
  };

  const showPrompt = async (request: AskRequest): Promise<AskAnswer> => {
    const ctx = uiCtx;
    if (!ctx?.hasUI) return { kind: "deny", reason: "no interactive UI is available" };
    const patterns = [...new Set(request.patterns)].map((p) => `${request.action} ${p}`).join(", ");
    const title = [`${request.who} needs permission for ${request.action}:`, ...request.lines.map((l) => `  ${l}`)].join("\n");
    const options = [
      "Allow once",
      `Always allow this session: ${patterns}`,
      `Always allow in this project: ${patterns}`,
      "Deny",
      "Deny with feedback…",
    ];
    const choice = await ctx.ui.select(title, options);
    switch (choice) {
      case options[0]:
        return { kind: "once" };
      case options[1]:
        return { kind: "session" };
      case options[2]:
        return { kind: "project" };
      case options[4]: {
        const feedback = await ctx.ui.input("Tell the agent why (or what to do instead)", "");
        return { kind: "deny", feedback: feedback?.trim() || undefined };
      }
      default:
        return { kind: "deny" };
    }
  };

  // ── pi-subagents integration (parent side) ──────────────────────────────

  pi.events.on("subagents:child:spawning", (data) => {
    const { agentName, parentSessionId } = (data ?? {}) as { agentName?: string; parentSessionId?: string };
    if (!agentName) return;
    const key = parentSessionId ?? node?.sessionId ?? "";
    const reg = registry();
    reg.spawning.set(key, [...(reg.spawning.get(key) ?? []), agentName]);
  });

  // Must stay synchronous: pi-subagents emits this right before binding the
  // child's extensions, and the child's copy of this extension looks it up.
  pi.events.on("subagents:child:session-created", (data) => {
    const { sessionId, parentSessionId } = (data ?? {}) as { sessionId?: string; parentSessionId?: string };
    if (!sessionId) return;
    const reg = registry();
    const parentId = parentSessionId ?? node?.sessionId;
    const queue = reg.spawning.get(parentId ?? "") ?? [];
    const agentName = queue.shift();
    reg.children.set(sessionId, { parentId, agentName });
    const childNode = reg.nodes.get(sessionId);
    if (childNode) {
      childNode.parentId ??= parentId;
      childNode.agentName ??= agentName;
    }
  });

  pi.events.on("subagents:child:disposed", (data) => {
    const { sessionId } = (data ?? {}) as { sessionId?: string };
    if (!sessionId) return;
    registry().children.delete(sessionId);
    registry().nodes.delete(sessionId);
  });

  // ── Lifecycle ───────────────────────────────────────────────────────────

  pi.on("session_start", (_event, ctx) => {
    register(ctx);
    reload(ctx);
  });

  pi.on("session_shutdown", () => {
    if (node) registry().nodes.delete(node.sessionId);
    node = undefined;
    uiCtx = undefined;
  });

  pi.on("before_agent_start", (event, ctx) => {
    register(ctx);
    // pi-subagents tags a child's system prompt with its agent name.
    const tag = /<active_agent name="([^"]+)"\s*\/>/.exec(event.systemPrompt ?? "");
    if (tag && node) node.agentName = tag[1];
    reload(ctx);
    // Hide tools that every rule denies, so the model does not try them.
    const current = rules(ctx);
    const selected = event.systemPromptOptions.selectedTools;
    const keep = selected.filter((tool) => !isFullyDenied(current, normalizeAction(tool)));
    if (keep.length !== selected.length) {
      selected.splice(0, selected.length, ...keep);
    }
  });

  // ── The gate ────────────────────────────────────────────────────────────

  pi.on("tool_call", async (event, ctx) => {
    register(ctx);
    if (ctx.hasUI) uiCtx = ctx;
    const current = rules(ctx);
    const input = (event.input ?? {}) as Record<string, unknown>;

    for (const check of checksFor(event.toolName, input, ctx.cwd)) {
      const decision = decide(check.action, check.resources, current, approvals(ctx));
      if (decision.effect === "allow") continue;

      if (decision.effect === "deny") {
        const res = decision.resources[0];
        const from = decision.rule?.source ? ` (rule ${decision.rule.action} ${decision.rule.resource} → deny, from ${decision.rule.source})` : "";
        return {
          block: true,
          reason: `${TAG} ${check.action} ${quote(res.value)} is denied for ${who()}${from}. Do not try to work around this; ask the user if it is needed.`,
        };
      }

      const prompter = node && prompterFor(node);
      const askLines = decision.resources.map(describe);
      if (!prompter?.prompt) {
        return {
          block: true,
          reason: `${TAG} ${check.action} ${askLines.join(", ")} needs approval, but no interactive UI is available to ask. Ask the user to allow it in permissions.json.`,
        };
      }
      const patterns = decision.resources.map((r) => check.patterns[check.resources.indexOf(r)] ?? "*");
      const answer = await prompter.prompt({
        who: who(),
        action: check.action,
        lines: askLines,
        patterns,
        stillNeeded: () => decide(check.action, check.resources, rules(ctx), approvals(ctx)).effect !== "allow",
      });

      if (answer.kind === "deny") {
        const why = answer.reason ? `: ${answer.reason}` : answer.feedback ? `. User feedback: ${answer.feedback}` : "";
        return { block: true, reason: `${TAG} The user denied ${check.action} ${askLines.join(", ")}${why}` };
      }
      const add = [...new Set(patterns)].map<Rule>((resource) => ({
        action: check.action,
        resource,
        effect: "allow",
        source: answer.kind === "project" ? "saved approval" : "session approval",
      }));
      if (answer.kind === "session" && node) rootOf(node).sessionApprovals.push(...add);
      if (answer.kind === "project") saveProjectApprovals(agentDir, ctx.cwd, add);
    }
    return undefined;
  });

  // ── /permissions ────────────────────────────────────────────────────────

  pi.registerCommand("permissions", {
    description: "Show the permission rules in effect; `/permissions clear` forgets approvals",
    handler: async (args, ctx) => {
      register(ctx);
      reload(ctx);
      if (args.trim() === "clear") {
        const root = node ? rootOf(node) : undefined;
        const session = root?.sessionApprovals.length ?? 0;
        if (root) root.sessionApprovals = [];
        const saved = clearProjectApprovals(agentDir, ctx.cwd);
        ctx.ui.notify(`${TAG} cleared ${session} session and ${saved} saved approvals for ${ctx.cwd}`, "info");
        return;
      }
      const lines = [`${TAG} agent: ${agentName() ?? "(unknown)"}, last matching rule wins`];
      for (const r of rules(ctx)) lines.push(`  ${r.action} ${r.resource} → ${r.effect}  (${r.source ?? "?"})`);
      const extra = approvals(ctx);
      if (extra.length) {
        lines.push("approvals (cannot override a deny):");
        for (const r of extra) lines.push(`  ${r.action} ${r.resource} → allow  (${r.source ?? "?"})`);
      }
      if (config?.errors.length) lines.push("config errors:", ...config.errors.map((e) => `  ${e}`));
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}

function quote(value: string): string {
  const short = value.length > 200 ? `${value.slice(0, 200)}…` : value;
  return `\`${short}\``;
}

function describe(res: Resource): string {
  return res.opaque ? `${quote(res.value)} (${res.reason ?? "cannot see what it runs"})` : quote(res.value);
}
