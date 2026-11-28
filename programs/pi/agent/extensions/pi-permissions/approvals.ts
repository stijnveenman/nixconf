import { mkdirSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { readJson } from "./config.ts";
import { parseRules, type Rule } from "./rules.ts";

/** "Always allow in this project" rules, per project directory. */
type Store = Record<string, Rule[]>;

function storePath(agentDir: string): string {
  return join(agentDir, "pi-permissions", "approvals.json");
}

function readStore(agentDir: string): Store {
  const json = readJson(storePath(agentDir), []) ?? {};
  return Object.fromEntries(
    Object.entries(json).map(([project, rules]) => [
      project,
      parseRules(rules, "saved approval").map((rule) => ({ ...rule, effect: "allow" as const })),
    ]),
  );
}

function writeStore(agentDir: string, store: Store): void {
  const path = storePath(agentDir);
  const plain = Object.fromEntries(
    Object.entries(store).map(([project, rules]) => [project, rules.map(({ action, resource }) => ({ action, resource, effect: "allow" }))]),
  );
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(plain, null, 2)}\n`);
  renameSync(tmp, path);
}

export function loadProjectApprovals(agentDir: string, project: string): Rule[] {
  return readStore(agentDir)[project] ?? [];
}

export function saveProjectApprovals(agentDir: string, project: string, add: Rule[]): void {
  const store = readStore(agentDir);
  const rules = store[project] ?? [];
  const isNew = (rule: Rule) => !rules.some((r) => r.action === rule.action && r.resource === rule.resource);
  store[project] = [...rules, ...add.filter(isNew)];
  writeStore(agentDir, store);
}

export function clearProjectApprovals(agentDir: string, project: string): number {
  const store = readStore(agentDir);
  const count = store[project]?.length ?? 0;
  if (count) {
    delete store[project];
    writeStore(agentDir, store);
  }
  return count;
}
