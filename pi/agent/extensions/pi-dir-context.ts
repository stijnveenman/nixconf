/**
 * Loads `.pi/AGENTS.md` (or `.pi/CLAUDE.md`) from the working directory and its
 * parent directories as extra context files, outermost first.
 */
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const NAMES = ["AGENTS.md", "CLAUDE.md"];

function collect(cwd: string): { path: string; content: string }[] {
  const found: { path: string; content: string }[] = [];
  let dir = resolve(cwd);
  for (;;) {
    for (const name of NAMES) {
      const path = join(dir, ".pi", name);
      if (existsSync(path)) {
        try {
          found.unshift({ path, content: readFileSync(path, "utf8") });
        } catch {}
        break;
      }
    }
    const parent = dirname(dir);
    if (parent === dir) return found;
    dir = parent;
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event) => {
    const have = new Set(event.systemPromptOptions.contextFiles.map((f) => f.path));
    for (const file of collect(event.systemPromptOptions.cwd)) {
      if (!have.has(file.path)) event.systemPromptOptions.contextFiles.push(file);
    }
  });
}
