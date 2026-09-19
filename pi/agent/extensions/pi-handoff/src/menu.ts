import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { defineMenu, runMenu } from "@narumitw/pi-tui-kit";
import {
  buildCompaction,
  generateTaskRecommendations,
  type TaskRecommendations,
} from "./commands.js";
import { showMultiLineInput } from "./multi-line-input.js";

type TaskContext = "none" | "compact" | "fork";
type Screen = "context" | "model" | "thinking" | "recommendations";
type Action = "selectContext" | "selectModel" | "selectThinking";
type HandoffModel = NonNullable<ExtensionCommandContext["model"]>;
type ThinkingLevel = NonNullable<ExtensionCommandContext["thinkingLevel"]>;

interface HandoffState {
  taskContext: TaskContext;
  task: string;
  compaction?: string;
  model?: HandoffModel;
  thinkingLevel?: ThinkingLevel;
  recommendations?: TaskRecommendations;
}

function modelKey(model: HandoffModel): string {
  return `${model.provider}/${model.id}`;
}

export async function showHandoffMenu(
  ctx: ExtensionCommandContext,
  onConfirm: (state: Readonly<HandoffState>) => void | Promise<void>,
) {
  const state: HandoffState = {
    taskContext: "none",
    task: "",
  };
  const models =
    ctx.scopedModels.length > 0
      ? ctx.scopedModels.map(({ model }) => model)
      : ctx.modelRegistry.getAvailable();
  const modelsByKey = new Map(models.map((model) => [modelKey(model), model]));

  const menu = defineMenu<HandoffState, Screen, Action>({
    start: "context",
    screens: {
      context: () => ({
        kind: "choice",
        title: "Task context",
        lines: ["Choose the context to pass to the new session."],
        items: [
          {
            id: "none",
            label: "None",
            description:
              "No task context, only user provided input will be passed to the new session.",
            details: ["Only the task text is passed to the new session."],
            searchText: "no none task only user input",
          },
          {
            id: "compact",
            label: "Compact",
            description:
              "Compact the current session, steering towards a task provided.",
            details: [
              "The current session will be compacted around the handoff task.",
            ],
            searchText: "summarize summary compact current session task",
          },
          {
            id: "fork",
            label: "Fork",
            description: "Provide the entire session, combined with the task.",
            details: [
              "The new session receives the full current session and task.",
            ],
            searchText: "full entire fork session task",
          },
        ],
        action: "selectContext",
        enableSearch: true,
        hint: "close",
      }),
      model: () => ({
        kind: "choice",
        title: "Model",
        lines: ["Choose the model for the new session."],
        items: models.map((model) => ({
          id: modelKey(model),
          label: model.name,
          description: modelKey(model),
          details: [modelKey(model)],
          searchText: modelKey(model),
        })),
        action: "selectModel",
        currentItemId: ctx.model ? modelKey(ctx.model) : undefined,
        enableSearch: true,
        hint: "back",
      }),
      thinking: () => {
        const levels = state.model
          ? getSupportedThinkingLevels(state.model)
          : ["off"];
        return {
          kind: "choice",
          title: "Thinking level",
          lines: [
            `Choose the thinking level for ${state.model?.name ?? "the new session"}.`,
          ],
          items: levels.map((level) => ({
            id: level,
            label: level,
            searchText: level,
          })),
          action: "selectThinking",
          currentItemId: state.thinkingLevel,
          enableSearch: true,
          hint: "back",
        };
      },
      recommendations: () => ({
        kind: "detail",
        title: "Task recommendations",
        lines: state.recommendations
          ? [
              `Model: ${state.recommendations.model}`,
              `Thinking: ${state.recommendations.thinking}`,
              `Branch: ${state.recommendations.branch}`,
              `Summary: ${state.recommendations.summary}`,
            ]
          : ["No recommendations were generated."],
        hint: "close",
      }),
    },
    actions: {
      selectContext: async ({ ctx: actionCtx, state, itemId, signal }) => {
        if (itemId !== "none" && itemId !== "compact" && itemId !== "fork") {
          return { kind: "stay" };
        }

        state.taskContext = itemId;
        const taskOutcome = await showMultiLineInput(actionCtx, {
          title: "Task",
          description: "Describe the task",
          signal,
        });
        if (taskOutcome.kind === "close") return { kind: "close" };
        if (taskOutcome.kind !== "confirm") return { kind: "stay" };

        state.task = taskOutcome.value ?? "";
        state.compaction = undefined;

        if (state.taskContext === "compact") {
          const summary = await buildCompaction(actionCtx, state.task);
          if (summary === undefined) return { kind: "stay" };
          state.compaction = summary;
        }

        if (models.length === 0) {
          actionCtx.ui.notify(
            "No models are available for the handoff.",
            "error",
          );
          return { kind: "stay" };
        }
        return { kind: "to", screen: "model" };
      },
      selectModel: async ({ state, itemId }) => {
        const model = modelsByKey.get(itemId);
        if (!model) return { kind: "stay" };

        state.model = model;
        const levels = getSupportedThinkingLevels(model);
        state.thinkingLevel = levels.includes(ctx.thinkingLevel ?? "off")
          ? (ctx.thinkingLevel ?? "off")
          : levels[0];
        return { kind: "to", screen: "thinking" };
      },
      selectThinking: async ({ state, itemId }) => {
        if (!state.model) return { kind: "back" };
        const levels = getSupportedThinkingLevels(state.model);
        if (!levels.includes(itemId as ThinkingLevel)) return { kind: "stay" };

        state.thinkingLevel = itemId as ThinkingLevel;
        const recommendations = await generateTaskRecommendations(
          ctx,
          state.task,
          state.taskContext,
          state.compaction,
        );
        if (!recommendations) return { kind: "stay" };
        state.recommendations = recommendations;
        await onConfirm(state);
        return { kind: "to", screen: "recommendations" };
      },
    },
  });

  return runMenu(ctx, menu, {
    getState: () => state,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(
        `The handoff menu is unavailable in ${mode} mode.`,
        "warning",
      );
    },
  });
}
