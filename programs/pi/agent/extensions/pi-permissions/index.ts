/**
 * pi-permissions: opencode v2-style allow/ask/deny rules for every tool call,
 * with pi-subagents support. See README.md.
 */

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { PermissionSession, TAG } from "./session.ts";
import { agentFromSystemPrompt, trackSubagents } from "./subagents.ts";

export default function piPermissions(pi: ExtensionAPI) {
  const session = new PermissionSession();

  trackSubagents(pi, () => session.sessionId);

  pi.on("session_start", (_event, ctx) => {
    session.register(ctx);
    session.reload(ctx);
  });

  pi.on("session_shutdown", () => session.unregister());

  pi.on("before_agent_start", (event, ctx) => {
    const node = session.register(ctx);
    node.agentName = agentFromSystemPrompt(event.systemPrompt) ?? node.agentName;
    session.reload(ctx);
    session.hideDeniedTools(ctx, event.systemPromptOptions.selectedTools);
    session.hideDeniedSkills(ctx, event.systemPromptOptions.skills);
  });

  pi.on("input", (event, ctx) => {
    session.register(ctx);
    const skill = session.deniedSkillCommand(ctx, event.text);
    if (!skill) return { action: "continue" as const };
    if (ctx.hasUI) ctx.ui.notify(`${TAG} skill ${skill} is denied by your permissions`, "warning");
    return { action: "handled" as const };
  });

  pi.on("tool_call", (event, ctx) => {
    session.register(ctx);
    return session.checkToolCall(event.toolName, (event.input ?? {}) as Record<string, unknown>, ctx);
  });

  pi.registerCommand("permissions", {
    description: "Show the permission rules in effect; `/permissions clear` forgets this session's approvals",
    handler: async (args, ctx) => showPermissions(session, args.trim(), ctx),
  });
}

function showPermissions(session: PermissionSession, args: string, ctx: ExtensionCommandContext): void {
  session.register(ctx);
  session.reload(ctx);
  if (args === "clear") {
    ctx.ui.notify(`${TAG} cleared ${session.clearApprovals()} session approvals`, "info");
    return;
  }
  const format = (r: { action: string; resource: string; effect: string; source?: string }) =>
    `  ${r.action} ${r.resource} → ${r.effect}  (${r.source ?? "?"})`;
  const approvals = session.approvals();
  const errors = session.configErrors;
  const lines = [
    `${TAG} agent: ${session.agentName ?? "(unknown)"}, last matching rule wins`,
    ...session.rules(ctx).map(format),
    ...(approvals.length ? ["approvals (cannot override a deny):", ...approvals.map(format)] : []),
    ...(errors.length ? ["config errors:", ...errors.map((e) => `  ${e}`)] : []),
  ];
  ctx.ui.notify(lines.join("\n"), "info");
}
