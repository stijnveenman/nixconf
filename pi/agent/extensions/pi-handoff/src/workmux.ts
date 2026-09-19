import { execFile, execFileSync } from "node:child_process";
import { promisify } from "node:util";
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

const execFileAsync = promisify(execFile);

export async function addWorkmuxAgent(agent: string, branch: string): Promise<string> {
  const result = await execFileAsync("workmux", [
    "add",
    "--background",
    "--agent",
    agent,
    branch,
  ]);
  return [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
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
