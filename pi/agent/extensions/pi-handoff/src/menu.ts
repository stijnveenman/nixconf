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
type Screen =
  | "context"
  | "recommendations"
  | "modelRecommendation"
  | "thinkingRecommendation"
  | "branchRecommendation"
  | "summaryRecommendation";
type Action =
  | "selectContext"
  | "selectModelRecommendation"
  | "selectThinkingRecommendation"
  | "updateBranch"
  | "updateSummary"
  | "confirm";
type HandoffModel = NonNullable<ExtensionCommandContext["model"]>;

interface HandoffState {
  taskContext: TaskContext;
  task: string;
  compaction?: string;
  recommendations?: TaskRecommendations;
}

function modelKey(model: HandoffModel): string {
  return `${model.provider}/${model.id}`;
}

function modelForRecommendation(
  recommendation: string,
  models: readonly HandoffModel[],
  fallback?: HandoffModel,
): HandoffModel | undefined {
  return (
    models.find(
      (model) => modelKey(model) === recommendation || model.name === recommendation,
    ) ?? fallback
  );
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
            details: ["The current session will be compacted around the handoff task."],
            searchText: "summarize summary compact current session task",
          },
          {
            id: "fork",
            label: "Fork",
            description: "Provide the entire session, combined with the task.",
            details: ["The new session receives the full current session and task."],
            searchText: "full entire fork session task",
          },
        ],
        action: "selectContext",
        enableSearch: true,
        hint: "close",
      }),
      recommendations: () => ({
        kind: "actions",
        title: "Task recommendations",
        lines: ["Update a recommendation or confirm the handoff."],
        items: state.recommendations
          ? [
              { id: "confirm", label: "Confirm", action: "confirm" },
              {
                id: "model",
                label: "Model",
                description: state.recommendations.model,
                action: "selectModelRecommendation",
              },
              {
                id: "thinking",
                label: "Thinking",
                description: state.recommendations.thinking,
                action: "selectThinkingRecommendation",
              },
              {
                id: "branch",
                label: "Branch",
                description: state.recommendations.branch,
                action: "updateBranch",
              },
              {
                id: "summary",
                label: "Summary",
                description: state.recommendations.summary,
                action: "updateSummary",
              },
            ]
          : [{ id: "close", label: "Close", close: true }],
        hint: "close",
      }),
      branchRecommendation: () => ({
        kind: "input",
        title: "Update branch recommendation",
        lines: ["Edit the branch name and press Enter to save."],
        initialValue: state.recommendations?.branch,
        action: "updateBranch",
        hint: "back",
      }),
      summaryRecommendation: () => ({
        kind: "input",
        title: "Update summary recommendation",
        lines: ["Edit the task summary and press Enter to save."],
        initialValue: state.recommendations?.summary,
        action: "updateSummary",
        hint: "back",
      }),
      modelRecommendation: () => {
        const recommendation = state.recommendations?.model;
        return {
          kind: "choice",
          title: "Update model recommendation",
          lines: ["Choose a model for the handoff."],
          items: models.map((model) => ({
            id: modelKey(model),
            label: model.name,
            description: modelKey(model),
            searchText: modelKey(model),
          })),
          action: "selectModelRecommendation",
          currentItemId: recommendation,
          enableSearch: true,
          hint: "back",
        };
      },
      thinkingRecommendation: () => {
        const model = modelForRecommendation(
          state.recommendations?.model ?? "",
          models,
          ctx.model,
        );
        const levels = model ? getSupportedThinkingLevels(model) : ["off"];
        return {
          kind: "choice",
          title: "Update thinking recommendation",
          lines: [`Choose a thinking level${model ? ` for ${model.name}` : ""}.`],
          items: levels.map((level) => ({ id: level, label: level })),
          action: "selectThinkingRecommendation",
          currentItemId: state.recommendations?.thinking,
          enableSearch: true,
          hint: "back",
        };
      },
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

        const recommendations = await generateTaskRecommendations(
          actionCtx,
          state.task,
          state.taskContext,
          state.compaction,
        );
        if (!recommendations) return { kind: "stay" };
        state.recommendations = recommendations;

        return { kind: "to", screen: "recommendations" };
      },
      selectModelRecommendation: async ({ state, itemId }) => {
        if (itemId === "model") return { kind: "to", screen: "modelRecommendation" };
        if (
          !state.recommendations ||
          !models.some((model) => modelKey(model) === itemId)
        ) {
          return { kind: "stay" };
        }
        state.recommendations.model = itemId;
        return { kind: "back" };
      },
      selectThinkingRecommendation: async ({ state, itemId }) => {
        if (itemId === "thinking") {
          return { kind: "to", screen: "thinkingRecommendation" };
        }
        if (!state.recommendations) return { kind: "stay" };
        const model = modelForRecommendation(
          state.recommendations.model,
          models,
          ctx.model,
        );
        const levels = model ? getSupportedThinkingLevels(model) : ["off"];
        if (!levels.includes(itemId as (typeof levels)[number])) {
          return { kind: "stay" };
        }
        state.recommendations.thinking = itemId;
        return { kind: "back" };
      },
      updateBranch: async ({ state, itemId, value }) => {
        if (itemId === "branch") return { kind: "to", screen: "branchRecommendation" };
        if (state.recommendations && value !== undefined) {
          state.recommendations.branch = value;
        }
        return { kind: "back" };
      },
      updateSummary: async ({ state, itemId, value }) => {
        if (itemId === "summary")
          return { kind: "to", screen: "summaryRecommendation" };
        if (state.recommendations && value !== undefined) {
          state.recommendations.summary = value;
        }
        return { kind: "back" };
      },
      confirm: async ({ state }) => {
        await onConfirm(state);
        return { kind: "close" };
      },
    },
  });

  return runMenu(ctx, menu, {
    getState: () => state,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`The handoff menu is unavailable in ${mode} mode.`, "warning");
    },
  });
}
