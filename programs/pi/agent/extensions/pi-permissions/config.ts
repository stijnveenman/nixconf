/**
 * Loads rules from config files and agent frontmatter, and keeps the
 * per-project "always allow" approvals on disk.
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { DEFAULT_RULES, parseRules, type Rule } from "./rules.ts";

export type Paths = {
  /** `~/.pi/agent` */
  agentDir: string;
  /** `.pi`, the project config dir name */
  configDirName: string;
  cwd: string;
  /** Whether project-local config may be read. */
  trusted: boolean;
};

type ConfigFile = {
  defaults: boolean | undefined;
  rules: Rule[];
  agents: Map<string, Rule[]>;
};

export type LoadedConfig = {
  errors: string[];
  /** Rules for `agent`, in evaluation order (without approvals). */
  rulesFor(agent: string | undefined): Rule[];
};

const PATH_ACTIONS = new Set(["read", "edit", "list", "external_directory"]);

/** Expands a leading `~` or `$HOME` in path-action patterns, like opencode. */
function expandHome(rules: Rule[]): Rule[] {
  const home = homedir();
  return rules.map((rule) => {
    if (!PATH_ACTIONS.has(rule.action)) return rule;
    const resource = rule.resource.replace(/^(~|\$HOME)(?=\/|$)/, home);
    return resource === rule.resource ? rule : { ...rule, resource };
  });
}

function readJson(path: string, errors: string[]): Record<string, unknown> | undefined {
  if (!existsSync(path)) return undefined;
  try {
    const value = JSON.parse(readFileSync(path, "utf8"));
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
    errors.push(`${path}: expected a JSON object`);
  } catch (error) {
    errors.push(`${path}: ${(error as Error).message}`);
  }
  return undefined;
}

function loadFile(path: string, label: string, errors: string[]): ConfigFile | undefined {
  const json = readJson(path, errors);
  if (!json) return undefined;
  const rules = expandHome([
    ...parseRules(json.permission, label, errors),
    ...parseRules(json.permissions, label, errors),
  ]);
  const agents = new Map<string, Rule[]>();
  const agentSpec = json.agents ?? json.agent;
  if (agentSpec && typeof agentSpec === "object") {
    for (const [name, spec] of Object.entries(agentSpec as Record<string, unknown>)) {
      if (!spec || typeof spec !== "object") continue;
      const s = spec as Record<string, unknown>;
      const source = `${label} agents.${name}`;
      agents.set(name, expandHome([...parseRules(s.permission, source, errors), ...parseRules(s.permissions, source, errors)]));
    }
  }
  const defaults = typeof json.defaults === "boolean" ? json.defaults : undefined;
  return { defaults, rules, agents };
}

/** `permission:` / `permissions:` from an agent's Markdown frontmatter. */
function loadAgentFrontmatter(
  paths: Paths,
  agent: string,
  parseFrontmatter: (content: string) => { frontmatter: Record<string, unknown> },
  errors: string[],
): Rule[] {
  const dirs = [{ dir: join(paths.agentDir, "agents"), label: "global" }];
  if (paths.trusted) dirs.push({ dir: join(paths.cwd, paths.configDirName, "agents"), label: "project" });
  // A project agent file replaces the global one, as in pi-subagents.
  let rules: Rule[] = [];
  for (const { dir, label } of dirs) {
    const file = join(dir, `${agent}.md`);
    if (!existsSync(file)) continue;
    try {
      const { frontmatter } = parseFrontmatter(readFileSync(file, "utf8"));
      const source = `${label} agent ${agent}.md`;
      rules = expandHome([
        ...parseRules(frontmatter.permission, source, errors),
        ...parseRules(frontmatter.permissions, source, errors),
      ]);
    } catch (error) {
      errors.push(`${file}: ${(error as Error).message}`);
    }
  }
  return rules;
}

export function loadConfig(
  paths: Paths,
  parseFrontmatter: (content: string) => { frontmatter: Record<string, unknown> },
): LoadedConfig {
  const errors: string[] = [];
  const files: ConfigFile[] = [];
  const global = loadFile(join(paths.agentDir, "permissions.json"), "global permissions.json", errors);
  if (global) files.push(global);
  if (paths.trusted) {
    const project = loadFile(join(paths.cwd, paths.configDirName, "permissions.json"), "project permissions.json", errors);
    if (project) files.push(project);
  }
  const useDefaults = files.reduce<boolean>((acc, f) => f.defaults ?? acc, true);
  const topLevel = files.flatMap((f) => f.rules);
  const agentCache = new Map<string, Rule[]>();

  return {
    errors,
    rulesFor(agent) {
      const base = [...(useDefaults ? DEFAULT_RULES : []), ...topLevel];
      if (!agent) return base;
      let agentRules = agentCache.get(agent);
      if (!agentRules) {
        agentRules = [
          ...files.flatMap((f) => f.agents.get(agent) ?? []),
          ...loadAgentFrontmatter(paths, agent, parseFrontmatter, errors),
        ];
        agentCache.set(agent, agentRules);
      }
      return [...base, ...agentRules];
    },
  };
}

// ── Saved approvals ("always allow in this project") ────────────────────────

function approvalsPath(agentDir: string): string {
  return join(agentDir, "pi-permissions", "approvals.json");
}

function readApprovals(agentDir: string): Record<string, Rule[]> {
  const json = readJson(approvalsPath(agentDir), []);
  const out: Record<string, Rule[]> = {};
  if (!json) return out;
  for (const [project, rules] of Object.entries(json)) {
    out[project] = parseRules(rules, "saved approval").map((r) => ({ ...r, effect: "allow" as const }));
  }
  return out;
}

export function loadProjectApprovals(agentDir: string, project: string): Rule[] {
  return readApprovals(agentDir)[project] ?? [];
}

function writeApprovals(agentDir: string, all: Record<string, Rule[]>): void {
  const path = approvalsPath(agentDir);
  const plain = Object.fromEntries(
    Object.entries(all).map(([p, rules]) => [p, rules.map(({ action, resource }) => ({ action, resource, effect: "allow" }))]),
  );
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(plain, null, 2)}\n`);
  renameSync(tmp, path);
}

export function saveProjectApprovals(agentDir: string, project: string, add: Rule[]): void {
  const all = readApprovals(agentDir);
  const existing = all[project] ?? [];
  for (const rule of add) {
    if (!existing.some((r) => r.action === rule.action && r.resource === rule.resource)) existing.push(rule);
  }
  all[project] = existing;
  writeApprovals(agentDir, all);
}

export function clearProjectApprovals(agentDir: string, project: string): number {
  const all = readApprovals(agentDir);
  const count = all[project]?.length ?? 0;
  if (!count) return 0;
  delete all[project];
  writeApprovals(agentDir, all);
  return count;
}
