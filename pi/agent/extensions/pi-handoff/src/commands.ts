import { readFileSync } from "node:fs";
import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { runTask } from "@narumitw/pi-tui-kit";
import {
  DEFAULT_COMPACTION_SETTINGS,
  buildSessionContext,
  estimateTokens,
  generateSummaryWithUsage,
} from "@earendil-works/pi-coding-agent";

/** Additional instructions applied to handoff compaction summaries. */
export const HANDOFF_COMPACTION_STEERING =
  "Keep only the relevant information for the given task. Preserve relevant decisions and constraints but remove progress not relevant to the task.";

const TASK_RECOMMENDATIONS_SYSTEM_PROMPT = readFileSync(
  new URL("../prompt/task-recommendations.md", import.meta.url),
  "utf8",
).trim();

export interface TaskRecommendations {
  model: string;
  thinking: string;
  branch: string;
  summary: string;
}

function parseTaskRecommendations(output: string): TaskRecommendations {
  const fields = new Map<string, string>();
  for (const line of output.split("\n")) {
    const match = line.match(/^(model|thinking|branch|summary)\s*:\s*(.+)$/i);
    if (match) fields.set(match[1].toLowerCase(), match[2].trim());
  }

  const model = fields.get("model");
  const thinking = fields.get("thinking");
  const branch = fields.get("branch");
  const summary = fields.get("summary");
  if (!model || !thinking || !branch || !summary) {
    throw new Error(
      `Task recommendation response did not contain all required fields.\n\nResponse:\n${output}`,
    );
  }
  return { model, thinking, branch, summary };
}

function lastSessionMessages(ctx: ExtensionCommandContext) {
  const messages = buildSessionContext(
    ctx.sessionManager.buildContextEntries(),
  ).messages;
  type ContextMessage = Extract<
    (typeof messages)[number],
    { role: "user" | "assistant" | "toolResult" }
  >;
  const selected: ContextMessage[] = [];
  let tokens = 0;
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (
      message.role !== "user" &&
      message.role !== "assistant" &&
      message.role !== "toolResult"
    ) {
      continue;
    }
    const messageTokens = estimateTokens(message);
    if (selected.length > 0 && tokens + messageTokens > 100_000) break;
    selected.push(message);
    tokens += messageTokens;
  }
  return selected.reverse();
}

export async function generateTaskRecommendations(
  ctx: ExtensionCommandContext,
  task: string,
  taskContext: "none" | "compact" | "fork",
  compaction?: string,
): Promise<TaskRecommendations | undefined> {
  const model = ctx.modelRegistry.find("github-copilot", "mai-code-1.1-flash");
  if (!model)
    throw new Error(
      "Recommendation model github-copilot/mai-code-1.1-flash is unavailable",
    );

  const result = await runTask(ctx, {
    label: "Generating task recommendations…",
    task: async ({ signal }) => {
      const contextMessages =
        taskContext === "fork" ? lastSessionMessages(ctx) : [];
      const promptContext =
        taskContext === "compact" && compaction
          ? `Background history:\n${compaction}\n\n`
          : "";
      const response = await ctx.modelRegistry.complete(
        model,
        {
          systemPrompt: TASK_RECOMMENDATIONS_SYSTEM_PROMPT,
          messages: [
            ...contextMessages,
            {
              role: "user",
              content: [
                { type: "text", text: `${promptContext}Task:\n${task}` },
              ],
              timestamp: Date.now(),
            },
          ],
        },
        { signal },
      );
      const output = response.content
        .filter(
          (content): content is { type: "text"; text: string } =>
            content.type === "text",
        )
        .map((content) => content.text)
        .join("\n");
      return parseTaskRecommendations(output);
    },
    onError: (_ctx, error) => {
      ctx.ui.notify(
        `Task recommendations failed: ${error instanceof Error ? error.message : String(error)}`,
        "error",
      );
    },
  });

  return result.kind === "completed" ? result.value : undefined;
}

/**
 * Build a compaction summary without changing the active session.
 *
 * This uses the active session's resolved context, model, thinking level, and
 * Pi's normal summarization pipeline. The result is returned as a string only;
 * it is not persisted and does not replace the current context.
 */
export async function buildCompaction(
  ctx: ExtensionCommandContext,
  task: string,
  onComplete?: (summary: string) => void | Promise<void>,
): Promise<string | undefined> {
  const model = ctx.model;
  if (!model) throw new Error("No active model is available for compaction");

  const result = await runTask(ctx, {
    label: "Generating compaction…",
    task: async ({ signal }) => {
      const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
      if (!auth.ok) throw new Error(auth.error);

      const headers = auth.headers
        ? Object.fromEntries(
            Object.entries(auth.headers).filter(
              (entry): entry is [string, string] => entry[1] !== null,
            ),
          )
        : undefined;

      const summary = await generateSummaryWithUsage(
        buildSessionContext(ctx.sessionManager.buildContextEntries()).messages,
        model,
        DEFAULT_COMPACTION_SETTINGS.reserveTokens,
        auth.apiKey,
        headers,
        signal,
        `${HANDOFF_COMPACTION_STEERING}\n\nTask:\n${task}`,
        undefined,
        ctx.thinkingLevel,
        undefined,
        auth.env,
        undefined,
        undefined,
        ctx.sessionManager.getSessionId(),
      );

      return summary.text;
    },
    onError: (_ctx, error) => {
      ctx.ui.notify(
        `Compaction failed: ${error instanceof Error ? error.message : String(error)}`,
        "error",
      );
    },
  });

  if (result.kind !== "completed") return undefined;
  await onComplete?.(result.value);
  return result.value;
}
