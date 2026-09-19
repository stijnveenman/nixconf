import { readFileSync, writeFileSync } from "node:fs";
import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import type { WorkmuxAgent } from "./workmux.js";
import { runTask } from "@narumitw/pi-tui-kit";
import {
  DEFAULT_COMPACTION_SETTINGS,
  buildSessionContext,
  estimateTokens,
  generateSummaryWithUsage,
  serializeConversation,
} from "@earendil-works/pi-coding-agent";

/** Additional instructions applied to handoff compaction summaries. */
export const HANDOFF_COMPACTION_STEERING =
  "Keep only the relevant information for the given task. Preserve relevant decisions and constraints but remove progress not relevant to the task.";

const TASK_RECOMMENDATIONS_PROMPT = readFileSync(
  new URL("../prompt/task-recommendations.md", import.meta.url),
  "utf8",
).trim();
const TASK_RECOMMENDATIONS_SYSTEM_PROMPT =
  "Generate task recommendations and only those recommendations.";

export interface TaskRecommendations {
  branch: string;
  agent: string;
}

function parseTaskRecommendations(output: string): TaskRecommendations {
  const fields = new Map<string, string>();
  const fieldPattern = /(?:^|\r?\n)\s*(?:[-*]\s*)?(branch|agent)\s*:\s*(.+?)\s*$/gim;
  for (const match of output.matchAll(fieldPattern)) {
    // Keep the last occurrence in case the model repeats the format or
    // includes an example before its final recommendations.
    fields.set(match[1].toLowerCase(), match[2].trim());
  }

  const branch = fields.get("branch");
  const agent = fields.get("agent");
  if (!branch || !agent) {
    throw new Error(
      `Task recommendation response did not contain all required fields.\n\nResponse:\n${output}`,
    );
  }
  return { branch, agent };
}

function lastSessionMessages(ctx: ExtensionCommandContext, maxTokens: number) {
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
    if (selected.length > 0 && tokens + messageTokens > maxTokens) break;
    selected.push(message);
    tokens += messageTokens;
  }
  return selected.reverse();
}

function buildBackgroundContext(
  ctx: ExtensionCommandContext,
  taskContext: "none" | "compact" | "fork",
  compaction: string | undefined,
  maxTokens: number,
): string {
  if (taskContext === "fork") {
    return serializeConversation(lastSessionMessages(ctx, maxTokens));
  }
  return taskContext === "compact" ? (compaction ?? "") : "";
}

function lowestInputTier(model: {
  contextWindow: number;
  cost: { tiers?: readonly { inputTokensAbove: number }[] };
}): number {
  return Math.min(
    model.contextWindow,
    ...(model.cost.tiers?.map((tier) => tier.inputTokensAbove) ?? []),
  );
}

function estimateTextTokens(text: string): number {
  return estimateTokens({
    role: "user",
    content: [{ type: "text", text }],
    timestamp: Date.now(),
  });
}

export async function generateTaskRecommendations(
  ctx: ExtensionCommandContext,
  task: string,
  taskContext: "none" | "compact" | "fork",
  compaction: string | undefined,
  agents: Record<string, WorkmuxAgent>,
): Promise<TaskRecommendations | undefined> {
  const model = ctx.modelRegistry.find("github-copilot", "gpt-5.6-luna");
  if (!model)
    throw new Error("Recommendation model github-copilot/gpt-5.6-luna is unavailable");

  const result = await runTask(ctx, {
    label: "Generating task recommendations…",
    task: async ({ signal }) => {
      const agentPrompt = Object.entries(agents)
        .map(([name, agent]) => `- ${name}:${agent.when ?? ""}`)
        .join("\n");
      const taskPrompt = TASK_RECOMMENDATIONS_PROMPT.replaceAll(
        "@task",
        task,
      ).replaceAll("@agents", agentPrompt);
      const inputLimit = lowestInputTier(model);
      const fixedInputTokens =
        estimateTextTokens(TASK_RECOMMENDATIONS_SYSTEM_PROMPT) +
        estimateTextTokens(taskPrompt);
      const background = buildBackgroundContext(
        ctx,
        taskContext,
        compaction,
        Math.max(
          0,
          Math.min(model.contextWindow - 64_000, inputLimit - fixedInputTokens),
        ),
      );
      const prompt = [background, taskPrompt].filter(Boolean).join("\n\n");
      writeFileSync("/tmp/pi-handoff-task-recommendations.txt", prompt);

      const response = await ctx.modelRegistry.complete(
        model,
        {
          systemPrompt: TASK_RECOMMENDATIONS_SYSTEM_PROMPT,
          messages: [
            {
              role: "user",
              content: [{ type: "text", text: prompt }],
              timestamp: Date.now(),
            },
          ],
          tools: [],
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
      const requestModel = auth.baseUrl ? { ...model, baseUrl: auth.baseUrl } : model;

      const summary = await generateSummaryWithUsage(
        buildSessionContext(ctx.sessionManager.buildContextEntries()).messages,
        requestModel,
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
