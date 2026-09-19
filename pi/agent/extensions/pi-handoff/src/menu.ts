import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { defineMenu, runMenu } from "@narumitw/pi-tui-kit";
import { showMultiLineInput } from "./multi-line-input.js";

type TaskContext = "none" | "compact" | "fork";
type Screen = "context";
type Action = "selectContext";

export async function showHandoffMenu(
  ctx: ExtensionCommandContext,
  onConfirm: (taskContext: TaskContext, task: string) => void | Promise<void>,
) {
  let taskContext: TaskContext = "none";
  let task = "";

  const menu = defineMenu<
    { taskContext: TaskContext; task: string },
    Screen,
    Action
  >({
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
            description: "No task context, only user provided input will be passed to the new session.",
            details: ["Only the task text is passed to the new session."],
            searchText: "no none task only user input",
          },
          {
            id: "compact",
            label: "Compact",
            description: "Compact the current session, steering towards a task provided.",
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
    },
    actions: {
      selectContext: async ({ ctx: actionCtx, itemId, signal }) => {
        if (itemId !== "none" && itemId !== "compact" && itemId !== "fork") {
          return { kind: "stay" };
        }

        taskContext = itemId;
        const taskOutcome = await showMultiLineInput(actionCtx, {
          title: "Task",
          description: "Describe the task",
          signal,
        });
        if (taskOutcome.kind === "close") return { kind: "close" };
        if (taskOutcome.kind !== "confirm") return { kind: "stay" };

        task = taskOutcome.value ?? "";
        await onConfirm(taskContext, task);
        return { kind: "close" };
      },
    },
  });

  return runMenu(ctx, menu, {
    getState: () => ({ taskContext, task }),
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`The handoff menu is unavailable in ${mode} mode.`, "warning");
    },
  });
}
