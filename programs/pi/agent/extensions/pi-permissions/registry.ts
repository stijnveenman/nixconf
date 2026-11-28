/**
 * State shared by every session's copy of this extension. pi-subagents runs
 * children in-process, each with its own copy and event bus, so the parent
 * records children here and a child looks up the parent that answers its asks.
 * `globalThis` + `Symbol.for` survive pi's per-extension module isolation.
 */

import type { Rule } from "./rules.ts";

export type AskRequest = {
  /** Who is asking, e.g. "main" or "subagent Explore". */
  who: string;
  action: string;
  /** Resources that need approval, with notes. */
  lines: string[];
  /** Patterns "always allow" would save, one per asking resource. */
  patterns: string[];
  /** Re-checked just before prompting, since an earlier answer may cover it. */
  stillNeeded: () => boolean;
};

export type AskAnswer =
  | { kind: "once" | "session" }
  | { kind: "deny"; feedback?: string; reason?: string };

export type PermissionNode = {
  sessionId: string;
  parentId?: string;
  agentName?: string;
  /** Approvals for this session tree; only the root's list is used. */
  sessionApprovals: Rule[];
  /** Set on nodes with a UI. */
  prompt?: (request: AskRequest) => Promise<AskAnswer>;
};

type Registry = {
  nodes: Map<string, PermissionNode>;
  /** Children announced by pi-subagents: child session id → parent session id. */
  children: Map<string, { parentId?: string; agentName?: string }>;
  /** Agent names announced by `subagents:child:spawning`, waiting for their session id. */
  spawning: Map<string, string[]>;
};

const KEY = Symbol.for("pi-permissions:registry");

export function registry(): Registry {
  const g = globalThis as unknown as Record<symbol, Registry | undefined>;
  return (g[KEY] ??= { nodes: new Map(), children: new Map(), spawning: new Map() });
}

/** The topmost node of `node`'s tree that is still registered. */
export function rootOf(node: PermissionNode): PermissionNode {
  const { nodes } = registry();
  let current = node;
  for (let i = 0; i < 16 && current.parentId; i++) {
    const parent = nodes.get(current.parentId);
    if (!parent) break;
    current = parent;
  }
  return current;
}

/** The nearest node, starting at `node`, that can show a prompt. */
export function prompterFor(node: PermissionNode): PermissionNode | undefined {
  const { nodes } = registry();
  let current: PermissionNode | undefined = node;
  for (let i = 0; i < 16 && current; i++) {
    if (current.prompt) return current;
    current = current.parentId ? nodes.get(current.parentId) : undefined;
  }
  return undefined;
}
