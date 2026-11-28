/**
 * Turns a tool call into the permission checks it needs: one action with the
 * resources it touches, plus `external_directory` for paths outside the project.
 */

import { homedir } from "node:os";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { alwaysPattern, normalizeAction, type Resource } from "./rules.ts";
import { scan } from "./shell.ts";

export type Check = {
  action: string;
  resources: Resource[];
  /** "Always allow" pattern for each resource, same order. */
  patterns: string[];
};

function expandTilde(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return homedir() + path.slice(1);
  return path;
}

function isInside(root: string, path: string): boolean {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

/** Project-relative path inside the project, absolute outside it (opencode). */
function pathResource(cwd: string, raw: string): { value: string; absolute: string; outside: boolean } {
  const absolute = resolve(cwd, expandTilde(raw));
  const outside = !isInside(cwd, absolute);
  return { value: outside ? absolute : relative(cwd, absolute) || ".", absolute, outside };
}

function externalCheck(dirs: string[]): Check | undefined {
  const unique = [...new Set(dirs)];
  if (!unique.length) return undefined;
  return {
    action: "external_directory",
    resources: unique.map((value) => ({ value })),
    patterns: unique.map((d) => `${d}/*`),
  };
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.length ? value : undefined;
}

export function checksFor(toolName: string, input: Record<string, unknown>, cwd: string): Check[] {
  const action = normalizeAction(toolName);
  const checks: Check[] = [];
  const external: string[] = [];

  switch (toolName) {
    case "bash": {
      const command = str(input.command) ?? "";
      const result = scan(command);
      for (const target of result.cdTargets) {
        if (/[$`]/.test(target)) continue;
        const p = pathResource(cwd, target);
        if (p.outside) external.push(p.absolute);
      }
      const ext = externalCheck(external);
      if (ext) checks.push(ext);
      const seen = new Set<string>();
      const resources: Resource[] = [];
      const patterns: string[] = [];
      for (const cmd of result.commands) {
        const key = `${cmd.opaque}:${cmd.text}`;
        if (seen.has(key)) continue;
        seen.add(key);
        resources.push({ value: cmd.text, opaque: cmd.opaque, reason: cmd.reason });
        patterns.push(cmd.opaque && cmd.words.length <= 1 ? cmd.text : alwaysPattern(cmd.words));
      }
      checks.push({ action: "shell", resources, patterns });
      return checks;
    }
    case "read":
    case "write":
    case "edit": {
      const raw = str(input.path) ?? str(input.file_path);
      if (!raw) break;
      const p = pathResource(cwd, raw);
      if (p.outside) external.push(dirname(p.absolute));
      const ext = externalCheck(external);
      if (ext) checks.push(ext);
      checks.push({ action, resources: [{ value: p.value }], patterns: [action === "read" ? p.value : "*"] });
      return checks;
    }
    case "grep":
    case "find":
    case "ls": {
      const raw = str(input.path);
      if (raw) {
        const p = pathResource(cwd, raw);
        if (p.outside) external.push(p.absolute);
      }
      const ext = externalCheck(external);
      if (ext) checks.push(ext);
      const value = toolName === "ls" ? (raw ? pathResource(cwd, raw).value : ".") : (str(input.pattern) ?? "*");
      checks.push({ action, resources: [{ value }], patterns: ["*"] });
      return checks;
    }
    case "subagent": {
      const agent = str(input.subagent_type) ?? "*";
      checks.push({ action: "subagent", resources: [{ value: agent }], patterns: [agent] });
      return checks;
    }
  }
  checks.push({ action, resources: [{ value: "*" }], patterns: ["*"] });
  return checks;
}
