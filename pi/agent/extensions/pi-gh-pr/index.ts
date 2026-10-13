/**
 * pi-gh-pr: watch the CI of the open PR for the current branch.
 *
 * - Looks for an open PR every 5 minutes.
 * - While checks are pending, polls every 15 seconds.
 * - All checks passed: stop watching.
 * - Failed checks: fetch failure logs, wait for the agent to be idle, and ask it
 *   to fix them, then go back to the 5 minute poll. The same CI run never
 *   triggers a second message; across pi instances an exclusive claim file
 *   ensures only one agent per PR run gets the message.
 */

import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const IDLE_MS = 5 * 60_000;
const ACTIVE_MS = 15_000;
const MAX_LOG_CHARS = 8_000;
const CLAIM_DIR = join(tmpdir(), "pi-gh-pr");

type Pr = { number: number; url: string; headRefOid: string; state: string };
type Check = { name: string; bucket: string; link: string; workflow?: string };

export default function (pi: ExtensionAPI) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let ctx: ExtensionContext | undefined;
  let cwd = "";
  let stopped = true;
  let finished = false;
  let pending: { text: string; key: string; pr: Pr } | undefined;
  const handled = new Set<string>();

  async function gh<T>(args: string[]): Promise<T | undefined> {
    const r = await pi.exec("gh", args, { cwd, timeout: 60_000 }).catch(() => undefined);
    if (!r || (r.code !== 0 && !(args[1] === "checks" && r.code === 8))) return undefined;
    try {
      return JSON.parse(r.stdout) as T;
    } catch {
      return undefined;
    }
  }

  async function failureLogs(failed: Check[]): Promise<string> {
    const runs = new Map<string, Check[]>();
    const other: Check[] = [];
    for (const c of failed) {
      const m = /\/actions\/runs\/(\d+)/.exec(c.link ?? "");
      if (m) runs.set(m[1], [...(runs.get(m[1]) ?? []), c]);
      else other.push(c);
    }
    const parts: string[] = [];
    for (const [id] of runs) {
      const r = await pi.exec("gh", ["run", "view", id, "--log-failed"], { cwd, timeout: 120_000 }).catch(() => undefined);
      let log = (r?.stdout ?? "").trim();
      if (log.length > MAX_LOG_CHARS) log = "...(truncated)\n" + log.slice(-MAX_LOG_CHARS);
      parts.push(`### run ${id}\n\`\`\`\n${log || "(no logs available)"}\n\`\`\``);
    }
    for (const c of other) parts.push(`### ${c.name}\nNo logs available; see ${c.link}`);
    return parts.join("\n\n");
  }

  /** Exclusive cross-instance claim. Returns true if we are the first. */
  function claim(key: string): boolean {
    try {
      mkdirSync(CLAIM_DIR, { recursive: true });
      writeFileSync(join(CLAIM_DIR, key), JSON.stringify({ pid: process.pid, cwd, at: Date.now() }), { flag: "wx" });
      return true;
    } catch {
      return false;
    }
  }

  function deliver() {
    if (!pending || !ctx) return;
    if (!ctx.isIdle()) return; // retried on agent_end
    const { text, key } = pending;
    pending = undefined;
    if (!claim(key)) return;
    pi.sendUserMessage(text);
  }

  function schedule(ms: number) {
    if (stopped) return;
    clearTimeout(timer);
    timer = setTimeout(() => void poll(), ms);
    timer.unref?.();
  }

  async function poll() {
    if (stopped || finished) return;
    const pr = await gh<Pr>(["pr", "view", "--json", "number,url,headRefOid,state"]);
    if (!pr || pr.state !== "OPEN") return schedule(IDLE_MS);

    const checks = await gh<Check[]>(["pr", "checks", "--json", "name,bucket,link,workflow"]);
    if (!checks || checks.length === 0) return schedule(IDLE_MS);

    if (checks.some((c) => c.bucket === "pending")) return schedule(ACTIVE_MS);

    const failed = checks.filter((c) => c.bucket === "fail" || c.bucket === "cancel");
    if (failed.length === 0) {
      finished = true; // everything passed
      ctx?.ui.notify(`PR #${pr.number}: all checks passed`, "info");
      return;
    }

    const key = createHash("sha1")
      .update([pr.url, pr.headRefOid, ...failed.map((c) => c.link || c.name).sort()].join("\n"))
      .digest("hex");
    if (!handled.has(key)) {
      handled.add(key);
      const logs = await failureLogs(failed);
      const list = failed.map((c) => `- ${c.workflow ? c.workflow + " / " : ""}${c.name}: ${c.link}`).join("\n");
      pending = {
        key,
        pr,
        text:
          `CI failed on PR #${pr.number} (${pr.url}) for commit ${pr.headRefOid.slice(0, 7)}.\n\n` +
          `Failed checks:\n${list}\n\nFailure logs:\n\n${logs}\n\n` +
          `Please investigate and fix these failures, then commit and push.`,
      };
      deliver();
    }
    schedule(IDLE_MS);
  }

  pi.on("session_start", (_e, c) => {
    ctx = c;
    cwd = c.cwd;
    stopped = false;
    finished = false;
    schedule(5_000);
  });

  pi.on("agent_end", () => {
    // Deliver after the agent settles.
    setTimeout(deliver, 500);
  });

  pi.on("session_shutdown", () => {
    stopped = true;
    clearTimeout(timer);
  });
}
