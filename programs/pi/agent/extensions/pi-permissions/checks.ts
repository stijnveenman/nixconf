import { homedir } from "node:os";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { alwaysPattern } from "./arity.ts";
import { normalizeAction, type Resource } from "./rules.ts";
import { scan } from "./shell/scan.ts";

export type Check = {
  action: string;
  resources: Resource[];
  /** The "always allow" pattern for each resource, in the same order. */
  patterns: string[];
};

type Input = Record<string, unknown>;
type PathInfo = { value: string; absolute: string; outside: boolean };

export function checksFor(toolName: string, input: Input, cwd: string): Check[] {
  switch (toolName) {
    case "bash":
      return shellChecks(str(input.command) ?? "", cwd);
    case "read":
    case "write":
    case "edit":
      return fileChecks(normalizeAction(toolName), str(input.path) ?? str(input.file_path), cwd);
    case "grep":
    case "find":
      return searchChecks(normalizeAction(toolName), str(input.pattern) ?? "*", str(input.path), cwd);
    case "ls":
      return listChecks(str(input.path), cwd);
    case "subagent": {
      const agent = str(input.subagent_type) ?? "*";
      return [single("subagent", agent, agent)];
    }
    default:
      return [single(normalizeAction(toolName), "*", "*")];
  }
}

function shellChecks(command: string, cwd: string): Check[] {
  const result = scan(command);
  const cdTargets = result.cdTargets.filter((target) => !/[$`]/.test(target)).map((target) => pathInfo(cwd, target));
  const commands = uniqueBy(result.commands, (c) => `${c.opaque}:${c.text}`);
  const shell: Check = {
    action: "shell",
    resources: commands.map((c) => ({ value: c.text, opaque: c.opaque, reason: c.reason })),
    patterns: commands.map((c) => (c.opaque && c.words.length <= 1 ? c.text : alwaysPattern(c.words))),
  };
  return [...externalChecks(cdTargets.filter((p) => p.outside).map((p) => p.absolute)), shell];
}

function fileChecks(action: string, path: string | undefined, cwd: string): Check[] {
  if (!path) return [single(action, "*", "*")];
  const info = pathInfo(cwd, path);
  const external = info.outside ? [dirname(info.absolute)] : [];
  return [...externalChecks(external), single(action, info.value, action === "read" ? info.value : "*")];
}

function searchChecks(action: string, pattern: string, path: string | undefined, cwd: string): Check[] {
  return [...externalFor(path, cwd), single(action, pattern, "*")];
}

function listChecks(path: string | undefined, cwd: string): Check[] {
  return [...externalFor(path, cwd), single("list", path ? pathInfo(cwd, path).value : ".", "*")];
}

function externalFor(path: string | undefined, cwd: string): Check[] {
  const info = path ? pathInfo(cwd, path) : undefined;
  return externalChecks(info?.outside ? [info.absolute] : []);
}

function externalChecks(dirs: string[]): Check[] {
  const unique = [...new Set(dirs)];
  if (!unique.length) return [];
  return [{ action: "external_directory", resources: unique.map((value) => ({ value })), patterns: unique.map((d) => `${d}/*`) }];
}

function single(action: string, value: string, pattern: string): Check {
  return { action, resources: [{ value }], patterns: [pattern] };
}

/** Project-relative inside the project, absolute outside it, like opencode. */
function pathInfo(cwd: string, raw: string): PathInfo {
  const absolute = resolve(cwd, expandTilde(raw));
  const rel = relative(cwd, absolute);
  const outside = rel.startsWith("..") || isAbsolute(rel);
  return { value: outside ? absolute : rel || ".", absolute, outside };
}

function expandTilde(path: string): string {
  return path === "~" || path.startsWith("~/") ? homedir() + path.slice(1) : path;
}

function uniqueBy<T>(items: T[], key: (item: T) => string): T[] {
  const seen = new Set<string>();
  return items.filter((item) => !seen.has(key(item)) && seen.add(key(item)) !== undefined);
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.length ? value : undefined;
}
