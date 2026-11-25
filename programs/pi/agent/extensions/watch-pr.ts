/**
 * /watch-pr: watch the current branch's pull request for failing CI checks and
 * review comments, and prompt the agent to fix them. Also exposed to the agent
 * as the `watch_pr` tool.
 *
 * - Polls only while the agent is idle.
 * - Failing CI logs are summarised by a cheap model before prompting.
 * - Stops after idleTimeoutMinutes (default 60) without activity (new failures/comments, pending checks, agent work).
 * - Any user prompt or Escape cancels the watch.
 * - While watching, bash commands that would post PR comments/reviews are blocked.
 *
 * Config (optional): `~/.pi/agent/watch-pr.json`, overridden per key by
 * `<project>/.pi/watch-pr.json` when the project is trusted.
 *   {
 *     "summaryModel": "github-copilot/claude-haiku-5.5", // "provider/id", bare id, or substring; default "haiku"
 *     "intervalSeconds": 30,
 *     "idleTimeoutMinutes": 60, // stop watching after this long without activity
 *     "ignoreAuthors": ["some-bot[bot]"],
 *     "ignoreBodyPatterns": ["Terraform Plan:"] // regexes; matching comments are ignored
 *   }
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CONFIG_DIR_NAME, getAgentDir, isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { hyperlink, matchesKey, truncateToWidth } from "@earendil-works/pi-tui";

type WatchSettings = {
  summaryModel: string;
  intervalSeconds: number;
  idleTimeoutMinutes: number;
  ignoreAuthors: string[];
  ignoreBodyPatterns: string[];
};

type Check = { name: string; state: string; bucket: string; link: string; workflow?: string };

type Comment = { id: string; author: string; body: string; url: string; createdAt: string };

type Thread = { path?: string; line?: number; comments: Comment[] };

type Watch = {
  number: number;
  owner: string;
  repo: string;
  url: string;
  startedAt: string;
  ctx: ExtensionContext;
  abort: AbortController;
  timer?: ReturnType<typeof setTimeout>;
  polling: boolean;
  seenComments: Set<string>;
  seenChecks: Set<string>;
  unsubscribeInput: () => void;
  // Widget state
  checks?: Check[];
  unresolvedThreads?: number;
  conflicting?: boolean;
  conflictNotified?: boolean;
  approval?: { decision: string | null; approvers: string[]; changeRequesters: string[] };
  activity?: string;
  fixing: boolean;
  error?: string;
  nextPollAt?: number;
  lastActivityAt: number;
};

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

function formatDuration(ms: number) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m${String(s % 60).padStart(2, "0")}s`;
  return `${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}m`;
}

const WIDGET = "watch-pr";
const LOG_TAIL_CHARS = 15_000;

const SUMMARY_PROMPT = `You summarise failing CI jobs for a coding agent that will fix them.
For each failing job give: the job name, the failing step, the exact key error messages
(quote them, include file:line when present), and the most likely cause in one sentence.
Be concise. Do not propose code changes. Ignore noise such as setup steps and warnings unrelated to the failure.`;

const NO_REPLY_NOTE = `IMPORTANT: Never reply to, react to, resolve, or post PR comments or reviews
(no \`gh pr comment\`, \`gh pr review\`, \`gh api\` comment/review mutations). Only change code.`;

const CONFIG_FILE = "watch-pr.json";

function configPaths(ctx: ExtensionContext): string[] {
  const paths = [join(getAgentDir(), CONFIG_FILE)];
  if (ctx.isProjectTrusted()) paths.push(join(ctx.cwd, CONFIG_DIR_NAME, CONFIG_FILE));
  return paths;
}

// Throws on unreadable or malformed config files.
function loadConfig(ctx: ExtensionContext): Partial<WatchSettings> {
  let merged: Partial<WatchSettings> = {};
  for (const path of configPaths(ctx)) {
    if (!existsSync(path)) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
      throw new Error(`${path}: ${(error as Error).message}`);
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error(`${path}: expected a JSON object`);
    merged = { ...merged, ...(parsed as Partial<WatchSettings>) };
  }
  for (const pattern of Array.isArray(merged.ignoreBodyPatterns) ? merged.ignoreBodyPatterns : []) {
    try {
      new RegExp(String(pattern));
    } catch (error) {
      throw new Error(`invalid ignoreBodyPatterns entry ${JSON.stringify(pattern)}: ${(error as Error).message}`);
    }
  }
  return merged;
}

function readSettings(ctx: ExtensionContext): WatchSettings {
  let raw: Partial<WatchSettings> = {};
  try {
    raw = loadConfig(ctx);
  } catch {
    // Reported when the watch starts; fall back to defaults if it breaks later.
  }
  return {
    summaryModel: typeof raw.summaryModel === "string" && raw.summaryModel ? raw.summaryModel : "haiku",
    intervalSeconds:
      typeof raw.intervalSeconds === "number" && raw.intervalSeconds >= 5 ? raw.intervalSeconds : 30,
    idleTimeoutMinutes:
      typeof raw.idleTimeoutMinutes === "number" && raw.idleTimeoutMinutes > 0 ? raw.idleTimeoutMinutes : 60,
    ignoreAuthors: Array.isArray(raw.ignoreAuthors) ? raw.ignoreAuthors.map(String) : [],
    ignoreBodyPatterns: Array.isArray(raw.ignoreBodyPatterns) ? raw.ignoreBodyPatterns.map(String) : [],
  };
}

function resolveSummaryModel(ctx: ExtensionContext, spec: string) {
  const available = ctx.modelRegistry.getAvailable();
  const slash = spec.indexOf("/");
  if (slash > 0) {
    const exact = ctx.modelRegistry.find(spec.slice(0, slash), spec.slice(slash + 1));
    if (exact) return exact;
  }
  const exactId = available.filter((m) => m.id === spec);
  const fuzzy = available.filter((m) => m.id.toLowerCase().includes(spec.toLowerCase()));
  for (const candidates of [exactId, fuzzy]) {
    if (candidates.length === 0) continue;
    // Prefer the active provider, then the newest-looking id.
    const sameProvider = candidates.filter((m) => m.provider === ctx.model?.provider);
    const pool = sameProvider.length > 0 ? sameProvider : candidates;
    return [...pool].sort((a, b) => b.id.localeCompare(a.id, undefined, { numeric: true }))[0];
  }
  return ctx.model;
}

// Best-effort detection of gh commands that post or edit PR comments/reviews.
function postsPrComment(command: string): boolean {
  if (/\bgh\s+(pr|issue)\s+(comment|review)\b/.test(command)) return true;
  for (const segment of command.split(/&&|\|\||;|\n|\|/)) {
    if (!/\bgh\s+api\b/.test(segment)) continue;
    if (/\bgraphql\b/.test(segment) && /\bmutation\b/i.test(segment)) return true;
    if (!/(comments|reviews|replies|reactions)/.test(segment)) continue;
    const writes =
      /(-X|--method)\s*['"]?(POST|PATCH|PUT|DELETE)/i.test(segment) ||
      /(^|\s)(-f|-F|--field|--raw-field|--input)(\s|=)/.test(segment);
    if (writes) return true;
  }
  return false;
}

export default function (pi: ExtensionAPI) {
  let watch: Watch | undefined;

  function stop(reason?: string) {
    const current = watch;
    if (!current) return;
    watch = undefined;
    current.abort.abort();
    if (current.timer) clearTimeout(current.timer);
    current.unsubscribeInput();
    current.ctx.ui.setWidget(WIDGET, undefined);
    if (reason) current.ctx.ui.notify(`Stopped watching PR #${current.number}: ${reason}`, "info");
  }

  function installWidget(w: Watch) {
    w.ctx.ui.setWidget(WIDGET, (tui, theme) => {
      let frame = 0;
      const interval = setInterval(() => {
        if (watch !== w) return clearInterval(interval);
        frame = (frame + 1) % SPINNER.length;
        tui.requestRender();
      }, 80);
      const sep = theme.fg("dim", " · ");
      const spin = () => theme.fg("accent", SPINNER[frame]!);

      function status(): string {
        if (w.activity) return w.activity;
        if (w.polling) return "polling…";
        if (!w.ctx.isIdle()) return w.fixing ? "agent fixing…" : "paused while agent works";
        if (w.nextPollAt && w.nextPollAt - Date.now() >= 1000) return `next poll in ${formatDuration(w.nextPollAt - Date.now())}`;
        return "polling…";
      }
      const busy = () =>
        w.polling || !!w.activity || !w.ctx.isIdle() || !w.nextPollAt || w.nextPollAt - Date.now() < 1000;

      function checksRow(): { icon: string; text: string; sub: string[] } {
        const checks = w.checks;
        if (!checks) return { icon: spin(), text: theme.fg("muted", "loading…"), sub: [] };
        if (checks.length === 0) return { icon: theme.fg("dim", "·"), text: theme.fg("muted", "no checks"), sub: [] };
        const failing = checks.filter((c) => c.bucket === "fail");
        const pending = checks.filter((c) => c.bucket === "pending").length;
        const passed = checks.filter((c) => c.bucket === "pass").length;
        const counts = [
          failing.length > 0 ? theme.fg("error", `${failing.length} failing`) : undefined,
          pending > 0 ? theme.fg("warning", `${pending} pending`) : undefined,
          passed > 0 ? theme.fg("success", `${passed} passed`) : undefined,
        ].filter(Boolean);
        const icon =
          pending > 0 ? spin() : failing.length > 0 ? theme.fg("error", "✗") : theme.fg("success", "✓");
        const sub = failing.slice(0, 3).map((c) => (c.workflow ? `${c.workflow} / ${c.name}` : c.name));
        if (failing.length > 3) sub.push(`+${failing.length - 3} more`);
        return { icon, text: counts.join(sep), sub };
      }

      function commentsRow(): { icon: string; text: string } {
        const n = w.unresolvedThreads;
        if (n === undefined) return { icon: spin(), text: theme.fg("muted", "loading…") };
        if (n === 0) return { icon: theme.fg("success", "✓"), text: theme.fg("muted", "no unresolved threads") };
        return { icon: theme.fg("warning", "●"), text: theme.fg("warning", `${n} unresolved thread${n === 1 ? "" : "s"}`) };
      }

      function approvalRow(): { icon: string; text: string } {
        const a = w.approval;
        if (!a) return { icon: spin(), text: theme.fg("muted", "loading…") };
        const names = (list: string[]) => theme.fg("dim", ` (${list.map((n) => `@${n}`).join(", ")})`);
        if (a.decision === "APPROVED") {
          return { icon: theme.fg("success", "✓"), text: theme.fg("success", "approved") + names(a.approvers) };
        }
        if (a.decision === "CHANGES_REQUESTED") {
          return { icon: theme.fg("error", "✗"), text: theme.fg("error", "changes requested") + names(a.changeRequesters) };
        }
        if (a.decision === "REVIEW_REQUIRED") {
          return { icon: theme.fg("warning", "●"), text: theme.fg("warning", "waiting for approval") + (a.approvers.length ? names(a.approvers) : "") };
        }
        if (a.approvers.length > 0) {
          return { icon: theme.fg("success", "✓"), text: theme.fg("success", "approved") + names(a.approvers) };
        }
        return { icon: theme.fg("dim", "·"), text: theme.fg("muted", "no approval required") };
      }

      return {
        render(width: number) {
          const tree = (s: string) => theme.fg("dim", s);
          const elapsed = formatDuration(Date.now() - Date.parse(w.startedAt));
          const checks = checksRow();
          const comments = commentsRow();
          const approval = approvalRow();
          const lines = [
            theme.fg("accent", "● ") +
              theme.fg("accent", theme.bold("Watching PR ")) + hyperlink(theme.fg("accent", theme.bold(`#${w.number}`)), w.url) +
              " " + theme.fg("dim", `${w.owner}/${w.repo}`) + sep + theme.fg("muted", elapsed),
            `${tree("├─")} ${checks.icon} ${theme.bold("Checks")}   ${checks.text}`,
            ...checks.sub.map((s) => `${tree("│")}     ${tree("⎿")} ${theme.fg("muted", s)}`),
            `${tree("├─")} ${comments.icon} ${theme.bold("Comments")} ${comments.text}`,
            `${tree("├─")} ${approval.icon} ${theme.bold("Approval")} ${approval.text}`,
            ...(w.conflicting ? [`${tree("├─")} ${theme.fg("error", "✗")} ${theme.bold("Conflicts")} ${theme.fg("error", "merge conflicts")}`] : []),
            `${tree("└─")} ${busy() ? spin() : theme.fg("dim", "◦")} ${theme.fg("muted", status())}`,
          ];
          if (w.error) lines.push(`     ${tree("⎿")} ${theme.fg("error", w.error)}`);
          return lines.map((line) => truncateToWidth(line, width));
        },
        invalidate() {},
        dispose() {
          clearInterval(interval);
        },
      };
    });
  }

  async function gh(w: Watch, args: string[]) {
    return pi.exec("gh", args, { cwd: w.ctx.cwd, signal: w.abort.signal, timeout: 60_000 });
  }

  async function fetchChecks(w: Watch): Promise<Check[]> {
    const res = await gh(w, [
      "pr", "checks", String(w.number), "-R", `${w.owner}/${w.repo}`,
      "--json", "name,state,bucket,link,workflow",
    ]);
    // `gh pr checks` exits non-zero for failing/pending checks but still prints JSON.
    const stdout = res.stdout.trim();
    if (stdout) {
      try {
        return JSON.parse(stdout) as Check[];
      } catch {
        // fall through to the error below
      }
    }
    if (/no checks reported/i.test(res.stderr)) return [];
    throw new Error(`gh pr checks: ${res.stderr.trim().split("\n")[0] || `exit ${res.code}`}`);
  }

  async function fetchComments(w: Watch) {
    const query = `query($owner:String!,$repo:String!,$number:Int!){
      repository(owner:$owner,name:$repo){ pullRequest(number:$number){
        state
        mergeable
        reviewDecision
        latestOpinionatedReviews(first:30){ nodes{ state author{login} } }
        comments(last:50){ nodes{ id author{login} body url createdAt } }
        reviews(last:50){ nodes{ id author{login} body url createdAt: submittedAt } }
        reviewThreads(last:100){ nodes{ isResolved path line
          comments(first:50){ nodes{ id author{login} body url createdAt } } } }
      } } }`;
    const res = await gh(w, [
      "api", "graphql", "-f", `query=${query}`,
      "-F", `owner=${w.owner}`, "-F", `repo=${w.repo}`, "-F", `number=${w.number}`,
    ]);
    if (res.code !== 0) throw new Error(res.stderr.trim() || "gh api graphql failed");
    const pr = JSON.parse(res.stdout).data.repository.pullRequest;
    const toComment = (n: any): Comment => ({
      id: n.id,
      author: n.author?.login ?? "ghost",
      body: (n.body ?? "").trim(),
      url: n.url,
      createdAt: n.createdAt ?? "",
    });
    return {
      state: pr.state as string,
      conflicting: pr.mergeable === "CONFLICTING",
      approval: {
        decision: (pr.reviewDecision ?? null) as string | null,
        approvers: (pr.latestOpinionatedReviews.nodes as any[]).filter((n) => n.state === "APPROVED").map((n) => n.author?.login ?? "ghost"),
        changeRequesters: (pr.latestOpinionatedReviews.nodes as any[]).filter((n) => n.state === "CHANGES_REQUESTED").map((n) => n.author?.login ?? "ghost"),
      },
      general: [...pr.comments.nodes, ...pr.reviews.nodes].map(toComment),
      threads: (pr.reviewThreads.nodes as any[])
        .filter((t) => !t.isResolved)
        .map((t): Thread => ({ path: t.path, line: t.line ?? undefined, comments: t.comments.nodes.map(toComment) })),
    };
  }

  async function failedLog(w: Watch, check: Check): Promise<string | undefined> {
    const job = check.link.match(/\/actions\/runs\/\d+\/job\/(\d+)/)?.[1];
    if (!job) return undefined;
    const res = await gh(w, ["run", "view", "--job", job, "--log-failed", "-R", `${w.owner}/${w.repo}`]);
    const log = res.stdout.trim();
    if (!log) return undefined;
    return log.length > LOG_TAIL_CHARS ? `…${log.slice(-LOG_TAIL_CHARS)}` : log;
  }

  async function summariseFailures(w: Watch, failed: Check[]): Promise<string> {
    const sections: string[] = [];
    for (const check of failed) {
      const log = await failedLog(w, check).catch(() => undefined);
      sections.push(`## ${check.workflow ? `${check.workflow} / ` : ""}${check.name}\n${check.link}\n\n${log ?? "(no log available)"}`);
    }
    const raw = sections.join("\n\n");
    const settings = readSettings(w.ctx);
    const model = resolveSummaryModel(w.ctx, settings.summaryModel);
    if (!model) return raw;
    w.activity = `summarising ${failed.length} failing check${failed.length === 1 ? "" : "s"} with ${model.id}…`;
    try {
      const response = await w.ctx.modelRegistry.complete(
        model,
        {
          systemPrompt: SUMMARY_PROMPT,
          messages: [{ role: "user", content: [{ type: "text", text: raw }], timestamp: Date.now() }],
        },
        { signal: w.abort.signal },
      );
      if (response.stopReason === "error" || response.stopReason === "aborted") throw new Error(response.errorMessage);
      const text = response.content
        .filter((c): c is { type: "text"; text: string } => c.type === "text")
        .map((c) => c.text)
        .join("\n")
        .trim();
      return text || raw;
    } catch (error) {
      if (w.abort.signal.aborted) throw error;
      return raw;
    }
  }

  function formatComment(c: Comment) {
    return `**@${c.author}** (${c.url}):\n${c.body}`;
  }

  async function poll(w: Watch) {
    const settings = readSettings(w.ctx);
    const ignoredAuthors = new Set(settings.ignoreAuthors);
    const ignoredBodies = settings.ignoreBodyPatterns.flatMap((p) => {
      try {
        return [new RegExp(p)];
      } catch {
        return [];
      }
    });
    const isIgnored = (c: Comment) => ignoredAuthors.has(c.author) || ignoredBodies.some((re) => re.test(c.body));

    const [checks, comments] = await Promise.all([fetchChecks(w), fetchComments(w)]);
    if (watch !== w) return;

    if (comments.state !== "OPEN") {
      stop(`PR is ${comments.state.toLowerCase()}`);
      return;
    }

    // Comments: unresolved review threads with unseen comments, plus general
    // comments/reviews posted after the watch started.
    const newThreads = comments.threads.filter((t) =>
      t.comments.some((c) => !w.seenComments.has(c.id) && !isIgnored(c)),
    );
    const newGeneral = comments.general.filter(
      (c) => c.body && !w.seenComments.has(c.id) && !isIgnored(c) && c.createdAt >= w.startedAt,
    );

    const failed = checks.filter((c) => c.bucket === "fail" && !w.seenChecks.has(`${c.name}|${c.link}`));
    w.checks = checks;
    w.unresolvedThreads = comments.threads.length;
    w.approval = comments.approval;
    w.conflicting = comments.conflicting;
    const newConflict = comments.conflicting && !w.conflictNotified;
    if (!comments.conflicting) w.conflictNotified = false;
    if (checks.some((c) => c.bucket === "pending")) w.lastActivityAt = Date.now();

    if (failed.length === 0 && newThreads.length === 0 && newGeneral.length === 0 && !newConflict) return;

    if (failed.length > 0) w.activity = "fetching failed logs…";
    let ciSummary: string | undefined;
    try {
      ciSummary = failed.length > 0 ? await summariseFailures(w, failed) : undefined;
    } finally {
      w.activity = undefined;
    }
    // Bail out if cancelled or the user started something meanwhile.
    if (watch !== w || !w.ctx.isIdle()) return;

    w.lastActivityAt = Date.now();
    if (newConflict) w.conflictNotified = true;
    for (const c of failed) w.seenChecks.add(`${c.name}|${c.link}`);
    for (const t of comments.threads) for (const c of t.comments) w.seenComments.add(c.id);
    for (const c of comments.general) w.seenComments.add(c.id);

    const parts = [`PR #${w.number} (${w.url}) needs attention.`];
    if (ciSummary) {
      parts.push(`## Failing CI checks\n\n${ciSummary}\n\nFix the failing checks.`);
    }
    if (newThreads.length > 0 || newGeneral.length > 0) {
      const sections: string[] = [];
      if (newThreads.length > 0) {
        sections.push(
          `### Unresolved review threads\n\n` +
            newThreads
              .map((t) => `#### ${t.path ?? "(file)"}${t.line ? `:${t.line}` : ""}\n\n${t.comments.map(formatComment).join("\n\n")}`)
              .join("\n\n"),
        );
      }
      if (newGeneral.length > 0) sections.push(`### New PR comments\n\n${newGeneral.map(formatComment).join("\n\n")}`);
      parts.push(
        `## Review feedback\n\n${sections.join("\n\n")}\n\nAddress the review feedback items above where they are valid.`,
      );
    }
    if (newConflict) {
      parts.push("## Merge conflicts\n\nThe PR has merge conflicts with its base branch. Merge or rebase the base branch, resolve the conflicts, and push.");
    }
    parts.push("Then commit and push.", NO_REPLY_NOTE);

    w.fixing = true;
    pi.sendUserMessage(parts.join("\n\n"));
  }

  function schedule(w: Watch, delayMs: number) {
    if (watch !== w) return;
    w.nextPollAt = Date.now() + delayMs;
    w.timer = setTimeout(async () => {
      if (watch !== w) return;
      if (!w.ctx.isIdle() || w.ctx.hasPendingMessages()) w.lastActivityAt = Date.now();
      const timeoutMinutes = readSettings(w.ctx).idleTimeoutMinutes;
      if (Date.now() - w.lastActivityAt >= timeoutMinutes * 60_000) {
        stop(`no activity for ${formatDuration(timeoutMinutes * 60_000)}`);
        return;
      }
      if (w.ctx.isIdle() && !w.ctx.hasPendingMessages() && !w.polling) {
        w.polling = true;
        w.fixing = false;
        try {
          await poll(w);
          w.error = undefined;
        } catch (error) {
          if (watch === w && !w.abort.signal.aborted) {
            w.error = `poll failed: ${(error as Error).message.split("\n")[0]}`;
          }
        } finally {
          w.polling = false;
        }
      }
      schedule(w, readSettings(w.ctx).intervalSeconds * 1000);
    }, delayMs);
  }

  async function start(ctx: ExtensionContext): Promise<{ ok: boolean; message: string; level: "info" | "warning" | "error" }> {
    stop();
    try {
      loadConfig(ctx);
    } catch (error) {
      return { ok: false, level: "error", message: `watch-pr config error: ${(error as Error).message}` };
    }
    const res = await pi.exec("gh", ["pr", "view", "--json", "number,url,state"], { cwd: ctx.cwd, timeout: 30_000 });
    if (res.code !== 0) {
      return { ok: false, level: "error", message: `No PR for the current branch: ${res.stderr.trim()}` };
    }
    const pr = JSON.parse(res.stdout) as { number: number; url: string; state: string };
    if (pr.state !== "OPEN") {
      return { ok: false, level: "warning", message: `PR #${pr.number} is ${pr.state.toLowerCase()}` };
    }
    const [, owner, repo] = pr.url.match(/github\.com\/([^/]+)\/([^/]+)\/pull\//) ?? [];
    if (!owner || !repo) {
      return { ok: false, level: "error", message: `Cannot parse PR url ${pr.url}` };
    }

    const w: Watch = {
      number: pr.number,
      owner,
      repo,
      url: pr.url,
      startedAt: new Date().toISOString(),
      ctx,
      abort: new AbortController(),
      polling: false,
      seenComments: new Set(),
      seenChecks: new Set(),
      unsubscribeInput: () => {},
      fixing: false,
      lastActivityAt: Date.now(),
    };
    w.unsubscribeInput = ctx.ui.onTerminalInput((data) => {
      if (matchesKey(data, "escape")) stop("escape pressed");
      return undefined;
    });
    watch = w;
    installWidget(w);
    schedule(w, 0);
    return { ok: true, level: "info", message: `Watching PR #${pr.number} (${pr.url})` };
  }

  pi.registerCommand("watch-pr", {
    description: "Watch the current branch's PR and fix failing CI checks and review comments",
    handler: async (_args, ctx) => {
      const result = await start(ctx);
      if (!result.ok) ctx.ui.notify(result.message, result.level);
    },
  });

  pi.registerTool({
    name: "watch_pr",
    label: "Watch PR",
    description:
      "Start watching the current branch's open pull request. While the agent is idle, failing CI checks and new review comments are polled and sent back as prompts to fix. Replaces any existing watch.",
    promptSnippet: "Watch the current branch's PR for failing CI and review comments",
    promptGuidelines: [
      "Use watch_pr right after creating a pull request, or when the user asks to watch, monitor or babysit the PR.",
    ],
    parameters: Type.Object({}),
    async execute(_id, _params, _signal, _onUpdate, ctx) {
      const result = await start(ctx);
      return {
        content: [{ type: "text", text: result.message }],
        details: { ok: result.ok },
        isError: !result.ok,
      };
    },
  });

  pi.on("input", async (event) => {
    if (watch && event.source !== "extension") stop("user prompt");
  });

  pi.on("tool_call", async (event) => {
    if (!watch || !isToolCallEventType("bash", event)) return;
    if (postsPrComment(event.input.command)) {
      return { block: true, reason: "watch-pr: posting PR comments or reviews is not allowed. Only change code." };
    }
  });

  pi.on("session_shutdown", async () => stop());
}
