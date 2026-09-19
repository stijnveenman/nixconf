import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import YAML from "yaml";

export interface WorkmuxAgent {
  type: string;
  when?: string;
  description?: string;
  project?: string;
  args?: string[];
}

export interface WorkmuxConfig {
  agents?: Record<string, WorkmuxAgent>;
}

export function loadWorkmuxConfig(path: string): WorkmuxConfig {
  if (!existsSync(path)) return {};
  return YAML.parse(readFileSync(path, "utf8")) ?? {};
}

function currentGitRoot(): string | undefined {
  try {
    return execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd: process.cwd(),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return undefined;
  }
}

export function loadWorkmuxAgents(): Record<string, WorkmuxAgent> {
  const globalConfig = loadWorkmuxConfig(
    join(homedir(), ".config", "workmux", "config.yaml"),
  );
  const gitRoot = currentGitRoot();
  const localConfig = gitRoot ? loadWorkmuxConfig(join(gitRoot, ".workmux.yaml")) : {};

  const agents = {
    ...(globalConfig.agents ?? {}),
    ...(localConfig.agents ?? {}),
  };
  const project = basename(gitRoot ?? process.cwd());

  return Object.fromEntries(
    Object.entries(agents).filter(
      ([, agent]) => agent.project === undefined || agent.project === project,
    ),
  );
}
