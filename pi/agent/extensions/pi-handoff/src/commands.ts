import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
  defineMenu,
  runMenu,
  runTask,
} from "@narumitw/pi-tui-kit";
import {
  DEFAULT_COMPACTION_SETTINGS,
  buildSessionContext,
  generateSummaryWithUsage,
} from "@earendil-works/pi-coding-agent";

/** Additional instructions applied to handoff compaction summaries. */
export const HANDOFF_COMPACTION_STEERING =
  "Keep only the relevant information for the given task. Preserve relevant decisions and constraints but remove progress not relevant to the task.";

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
            Object.entries(auth.headers).filter((entry): entry is [string, string] => entry[1] !== null),
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
      ctx.ui.notify(`Compaction failed: ${error instanceof Error ? error.message : String(error)}`, "error");
    },
  });

  if (result.kind !== "completed") return undefined;
  await onComplete?.(result.value);
  return result.value;
}

export async function showCompactionDetails(
  ctx: ExtensionCommandContext,
  summary: string,
) {
  const menu = defineMenu<undefined, "summary", "close">({
    start: "summary",
    screens: {
      summary: () => ({
        kind: "detail",
        title: "Generated compaction",
        lines: summary.split("\n"),
        hint: "close",
      }),
    },
    actions: {
      close: async () => ({ kind: "close" }),
    },
  });

  return runMenu(ctx, menu, {
    getState: () => undefined,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`Compaction details are unavailable in ${mode} mode.`, "warning");
    },
  });
}
