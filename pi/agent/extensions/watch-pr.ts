/**
 * /watch-pr: watch the current branch's pull request for failing CI checks and
 * review comments, and prompt the agent to fix them.
 *
 * - Polls only while the agent is idle.
 * - Failing CI logs are summarised by a cheap model before prompting.
 * - Any user prompt or Escape cancels the watch.
 * - While watching, bash commands that would post PR comments/reviews are blocked.
 *
 * Settings (`settings.json`, optional):
 *   "watchPr": {
 *     "summaryModel": "github-copilot/claude-haiku-5.5", // "provider/id", bare id, or substring; default "haiku"
 *     "intervalSeconds": 30,
 *     "ignoreAuthors": ["codecov[bot]"]
 *   }
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

type WatchSettings = { summaryModel: string; intervalSeconds: number; ignoreAuthors: string[] };

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
};

const WIDGET = "watch-pr";
const LOG_TAIL_CHARS = 15_000;

const SUMMARY_PROMPT = `You summarise failing CI jobs for a coding agent that will fix them.
For each failing job give: the job name, the failing step, the exact key error messages
(quote them, include file:line when present), and the most likely cause in one sentence.
Be concise. Do not propose code changes. Ignore noise such as setup steps and warnings unrelated to the failure.`;

const NO_REPLY_NOTE = `IMPORTANT: Never reply to, react to, resolve, or post PR comments or reviews
(no \`gh pr comment\`, \`gh pr review\`, \`gh api\` comment/review mutations). Only change code.`;

function readSettings(pi: ExtensionAPI): WatchSettings {
  const raw = ((pi.getSettings() as Record<string, unknown>).watchPr ?? {}) as Partial<WatchSettings>;
  return {
    summaryModel: typeof raw.summaryModel === "string" && raw.summaryModel ? raw.summaryModel : "haiku",
    intervalSeconds:
      typeof raw.intervalSeconds === "number" && raw.intervalSeconds >= 5 ? raw.intervalSeconds : 30,
    ignoreAuthors: Array.isArray(raw.ignoreAuthors) ? raw.ignoreAuthors.map(String) : [],
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

  function setWidget(w: Watch, detail?: string) {
    const theme = w.ctx.ui.theme;
    const line = theme.fg("accent", `watching pr #${w.number}`) + (detail ? theme.fg("dim", ` · ${detail}`) : "");
    w.ctx.ui.setWidget(WIDGET, [line]);
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
    try {
      return JSON.parse(res.stdout || "[]") as Check[];
    } catch {
      return [];
    }
  }

  async function fetchComments(w: Watch) {
    const query = `query($owner:String!,$repo:String!,$number:Int!){
      repository(owner:$owner,name:$repo){ pullRequest(number:$number){
        state
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
    const settings = readSettings(pi);
    const model = resolveSummaryModel(w.ctx, settings.summaryModel);
    if (!model) return raw;
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
    const settings = readSettings(pi);
    const ignored = new Set(settings.ignoreAuthors);

    const [checks, comments] = await Promise.all([fetchChecks(w), fetchComments(w)]);
    if (watch !== w) return;

    if (comments.state !== "OPEN") {
      stop(`PR is ${comments.state.toLowerCase()}`);
      return;
    }

    // Comments: unresolved review threads with unseen comments, plus general
    // comments/reviews posted after the watch started.
    const newThreads = comments.threads.filter((t) =>
      t.comments.some((c) => !w.seenComments.has(c.id) && !ignored.has(c.author)),
    );
    const newGeneral = comments.general.filter(
      (c) => c.body && !w.seenComments.has(c.id) && !ignored.has(c.author) && c.createdAt >= w.startedAt,
    );

    const failed = checks.filter((c) => c.bucket === "fail" && !w.seenChecks.has(`${c.name}|${c.link}`));
    const pending = checks.filter((c) => c.bucket === "pending").length;
    const failing = checks.filter((c) => c.bucket === "fail").length;
    setWidget(w, pending > 0 ? `${pending} checks pending` : failing > 0 ? `${failing} checks failing` : checks.length > 0 ? "checks passing" : undefined);

    if (failed.length === 0 && newThreads.length === 0 && newGeneral.length === 0) return;

    setWidget(w, failed.length > 0 ? "summarising ci failure" : "new comments");
    const ciSummary = failed.length > 0 ? await summariseFailures(w, failed) : undefined;
    // Bail out if cancelled or the user started something meanwhile.
    if (watch !== w || !w.ctx.isIdle()) return;

    for (const c of failed) w.seenChecks.add(`${c.name}|${c.link}`);
    for (const t of comments.threads) for (const c of t.comments) w.seenComments.add(c.id);
    for (const c of comments.general) w.seenComments.add(c.id);

    const parts = [`PR #${w.number} (${w.url}) needs attention.`];
    if (ciSummary) parts.push(`## Failing CI checks\n\n${ciSummary}`);
    if (newThreads.length > 0) {
      parts.push(
        `## Unresolved review threads\n\n` +
          newThreads
            .map((t) => `### ${t.path ?? "(file)"}${t.line ? `:${t.line}` : ""}\n\n${t.comments.map(formatComment).join("\n\n")}`)
            .join("\n\n"),
      );
    }
    if (newGeneral.length > 0) parts.push(`## New PR comments\n\n${newGeneral.map(formatComment).join("\n\n")}`);
    parts.push(
      "Fix the failing checks and address the review feedback where it is valid. " +
        "Then commit and push so CI re-runs.",
      NO_REPLY_NOTE,
    );

    setWidget(w, "fixing");
    pi.sendUserMessage(parts.join("\n\n"));
  }

  function schedule(w: Watch, delayMs: number) {
    if (watch !== w) return;
    w.timer = setTimeout(async () => {
      if (watch !== w) return;
      if (w.ctx.isIdle() && !w.ctx.hasPendingMessages() && !w.polling) {
        w.polling = true;
        try {
          await poll(w);
        } catch (error) {
          if (watch === w && !w.abort.signal.aborted) {
            setWidget(w, `poll failed: ${(error as Error).message.split("\n")[0]}`);
          }
        } finally {
          w.polling = false;
        }
      }
      schedule(w, readSettings(pi).intervalSeconds * 1000);
    }, delayMs);
  }

  pi.registerCommand("watch-pr", {
    description: "Watch the current branch's PR and fix failing CI checks and review comments",
    handler: async (_args, ctx) => {
      stop();
      const res = await pi.exec("gh", ["pr", "view", "--json", "number,url,state"], { cwd: ctx.cwd, timeout: 30_000 });
      if (res.code !== 0) {
        ctx.ui.notify(`No PR for the current branch: ${res.stderr.trim()}`, "error");
        return;
      }
      const pr = JSON.parse(res.stdout) as { number: number; url: string; state: string };
      if (pr.state !== "OPEN") {
        ctx.ui.notify(`PR #${pr.number} is ${pr.state.toLowerCase()}`, "warning");
        return;
      }
      const [, owner, repo] = pr.url.match(/github\.com\/([^/]+)\/([^/]+)\/pull\//) ?? [];
      if (!owner || !repo) {
        ctx.ui.notify(`Cannot parse PR url ${pr.url}`, "error");
        return;
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
      };
      w.unsubscribeInput = ctx.ui.onTerminalInput((data) => {
        if (matchesKey(data, "escape")) stop("escape pressed");
        return undefined;
      });
      watch = w;
      setWidget(w);
      schedule(w, 0);
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
