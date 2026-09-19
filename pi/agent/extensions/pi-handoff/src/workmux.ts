import { execFile, execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { promisify } from "node:util";
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

export async function addWorkmuxAgent(
  agent: string,
  branch: string,
  task: string,
  compaction?: string,
  forkSessionId?: string,
): Promise<string> {
  const safeBranch = branch.replace(/[^a-zA-Z0-9._-]/g, "-");
  const promptFile = join(tmpdir(), `pi-hand-off-${safeBranch}.md`);
  writeFileSync(
    promptFile,
    compaction ? `Background:\n${compaction}\n\nTask:\n${task}\n` : `${task}\n`,
    "utf8",
  );

  const args = ["add", "--background", "--agent", agent, "--prompt-file", promptFile];
  if (forkSessionId) args.push("--fork", forkSessionId);
  args.push(branch);

  const result = await execFileAsync("workmux", args);
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
