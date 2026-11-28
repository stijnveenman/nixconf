import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DEFAULT_RULES, parseRules, type Rule } from "./rules.ts";

export type Paths = {
  /** `~/.pi/agent` */
  agentDir: string;
  /** `.pi`, the project config directory name. */
  configDirName: string;
  cwd: string;
  /** Project-local config is only read for trusted projects. */
  trusted: boolean;
};

export type ParseFrontmatter = (content: string) => { frontmatter: Record<string, unknown> };

export type LoadedConfig = {
  errors: string[];
  /** Rules for `agent` in evaluation order, without approvals. */
  rulesFor(agent: string | undefined): Rule[];
};

type ConfigFile = {
  defaults?: boolean;
  rules: Rule[];
  agents: Map<string, Rule[]>;
};

const PATH_ACTIONS = new Set(["read", "edit", "list", "external_directory"]);

export function loadConfig(paths: Paths, parseFrontmatter: ParseFrontmatter): LoadedConfig {
  const errors: string[] = [];
  const files = configFiles(paths)
    .map(({ path, label }) => loadFile(path, label, errors))
    .filter((file): file is ConfigFile => file !== undefined);
  const useDefaults = files.reduce<boolean>((acc, file) => file.defaults ?? acc, true);
  const base = [...(useDefaults ? DEFAULT_RULES : []), ...files.flatMap((file) => file.rules)];
  const agentRules = new Map<string, Rule[]>();

  const loadAgent = (agent: string) => [
    ...files.flatMap((file) => file.agents.get(agent) ?? []),
    ...loadAgentFrontmatter(paths, agent, parseFrontmatter, errors),
  ];

  return {
    errors,
    rulesFor(agent) {
      if (!agent) return base;
      if (!agentRules.has(agent)) agentRules.set(agent, loadAgent(agent));
      return [...base, ...agentRules.get(agent)!];
    },
  };
}

function configFiles(paths: Paths): { path: string; label: string }[] {
  const files = [{ path: join(paths.agentDir, "permissions.json"), label: "global permissions.json" }];
  if (paths.trusted) files.push({ path: join(paths.cwd, paths.configDirName, "permissions.json"), label: "project permissions.json" });
  return files;
}

function loadFile(path: string, label: string, errors: string[]): ConfigFile | undefined {
  const json = readJson(path, errors);
  if (!json) return undefined;
  const agents = new Map<string, Rule[]>();
  for (const [name, spec] of Object.entries(asObject(json.agents ?? json.agent))) {
    agents.set(name, permissionRules(asObject(spec), `${label} agents.${name}`, errors));
  }
  const defaults = typeof json.defaults === "boolean" ? json.defaults : undefined;
  return { defaults, rules: permissionRules(json, label, errors), agents };
}

/** A project agent file replaces the global one, as in pi-subagents. */
function loadAgentFrontmatter(paths: Paths, agent: string, parseFrontmatter: ParseFrontmatter, errors: string[]): Rule[] {
  const candidates = [{ file: join(paths.agentDir, "agents", `${agent}.md`), label: "global" }];
  if (paths.trusted) candidates.push({ file: join(paths.cwd, paths.configDirName, "agents", `${agent}.md`), label: "project" });
  const found = candidates.filter(({ file }) => existsSync(file)).at(-1);
  if (!found) return [];
  try {
    const { frontmatter } = parseFrontmatter(readFileSync(found.file, "utf8"));
    return permissionRules(frontmatter, `${found.label} agent ${agent}.md`, errors);
  } catch (error) {
    errors.push(`${found.file}: ${(error as Error).message}`);
    return [];
  }
}

/** Both the v1 `permission` and the v2 `permissions` keys. */
function permissionRules(spec: Record<string, unknown>, source: string, errors: string[]): Rule[] {
  return expandHome([...parseRules(spec.permission, source, errors), ...parseRules(spec.permissions, source, errors)]);
}

function expandHome(rules: Rule[]): Rule[] {
  return rules.map((rule) =>
    PATH_ACTIONS.has(rule.action) ? { ...rule, resource: rule.resource.replace(/^(~|\$HOME)(?=\/|$)/, homedir()) } : rule,
  );
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
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
