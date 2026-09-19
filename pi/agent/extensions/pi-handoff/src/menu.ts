import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { defineMenu, runMenu } from "@narumitw/pi-tui-kit";
import { buildCompaction } from "./commands.js";
import { showMultiLineInput } from "./multi-line-input.js";

type TaskContext = "none" | "compact" | "fork";
type Screen = "context" | "model";
type Action = "selectContext" | "selectModel";
type HandoffModel = NonNullable<ExtensionCommandContext["model"]>;

interface HandoffState {
  taskContext: TaskContext;
  task: string;
  compaction?: string;
  model?: HandoffModel;
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
        title: "Handoff model",
        lines: [
          state.compaction
            ? "Compaction generated. Choose the model for the new session."
            : "Choose the model for the new session.",
        ],
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
        await onConfirm(state);
        return { kind: "close" };
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
