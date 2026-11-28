import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registry } from "./registry.ts";

type SpawningEvent = { agentName?: string; parentSessionId?: string };
type ChildEvent = { sessionId?: string; parentSessionId?: string };

const ACTIVE_AGENT_TAG = /<active_agent name="([^"]+)"\s*\/>/;

/** pi-subagents puts `<active_agent name="…"/>` in a child's system prompt. */
export function agentFromSystemPrompt(systemPrompt: string | undefined): string | undefined {
  return ACTIVE_AGENT_TAG.exec(systemPrompt ?? "")?.[1];
}

/**
 * Records the children pi-subagents announces on this session's event bus, so
 * the child's own copy of this extension can find its parent and agent name.
 */
export function trackSubagents(pi: ExtensionAPI, currentSessionId: () => string | undefined): void {
  pi.events.on("subagents:child:spawning", (data) => {
    const { agentName, parentSessionId } = (data ?? {}) as SpawningEvent;
    if (!agentName) return;
    const key = parentSessionId ?? currentSessionId() ?? "";
    const { spawning } = registry();
    spawning.set(key, [...(spawning.get(key) ?? []), agentName]);
  });

  // Must stay synchronous: it is emitted right before the child's extensions bind.
  pi.events.on("subagents:child:session-created", (data) => {
    const { sessionId, parentSessionId } = (data ?? {}) as ChildEvent;
    if (!sessionId) return;
    const { spawning, children, nodes } = registry();
    const parentId = parentSessionId ?? currentSessionId();
    const agentName = spawning.get(parentId ?? "")?.shift();
    children.set(sessionId, { parentId, agentName });
    const child = nodes.get(sessionId);
    if (child) {
      child.parentId ??= parentId;
      child.agentName ??= agentName;
    }
  });

  pi.events.on("subagents:child:disposed", (data) => {
    const { sessionId } = (data ?? {}) as ChildEvent;
    if (!sessionId) return;
    registry().children.delete(sessionId);
    registry().nodes.delete(sessionId);
  });
}
