import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import {
  defineMenu,
  formatInteractionHints,
  HorizontalRule,
  renderBoundedFrame,
  runCustomInteraction,
  runMenu,
} from "@narumitw/pi-tui-kit";
import { showMultiLineInput } from "./multi-line-input.js";

type TaskContext = "none" | "compact" | "fork";
type Screen = "context";
type Action = "editContext";

function taskContextLabel(context: TaskContext): string {
  return context[0].toUpperCase() + context.slice(1);
}

async function showHandoffSummary(
  ctx: ExtensionCommandContext,
  taskContext: TaskContext,
  task: string,
  signal: AbortSignal,
): Promise<"confirmed" | "back" | "close"> {
  const result = await runCustomInteraction<"confirmed" | "back" | "close">(ctx, {
    signal,
    create: ({ tui, theme, keybindings, complete }) => {
      const rule = new HorizontalRule({
        ruleStyle: (text) => theme.fg("border", text),
      });
      const hint = formatInteractionHints(keybindings, [
        { bindings: ["tui.input.submit"], label: "confirm" },
        {
          bindings: ["tui.select.cancel"],
          excludeKeys: ["ctrl+c"],
          label: "back",
        },
        { keys: ["ctrl+c"], label: "close" },
      ]);

      return {
        render: (width: number) => {
          const safeWidth = Math.max(1, width);
          return renderBoundedFrame({
            width: safeWidth,
            maxRows: Math.max(1, Math.floor(tui.terminal.rows) - 3),
            rule: rule.render(safeWidth)[0] ?? "",
            title: [theme.fg("accent", theme.bold("Confirm handoff"))],
            context: [
              theme.fg("muted", `Context: ${taskContextLabel(taskContext)}`),
              theme.fg("muted", "Task:"),
            ],
            content: wrapTextWithAnsi(task, safeWidth),
            hints: ["", theme.fg("dim", hint)],
            compactHint: theme.fg("dim", hint),
            priorityRows: [0],
          });
        },
        invalidate() {},
        handleInput: (data: string) => {
          if (matchesKey(data, Key.ctrl("c"))) complete("close");
          else if (keybindings.matches(data, "tui.select.cancel")) complete("back");
          else if (keybindings.matches(data, "tui.input.submit")) complete("confirmed");
          tui.requestRender();
        },
      };
    },
  });

  return result.kind === "completed" ? result.value : "close";
}

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
        action: "editContext",
        enableSearch: true,
        hint: "close",
      }),
    },
    actions: {
      editContext: async ({ ctx, itemId, signal }) => {
        if (itemId !== "none" && itemId !== "compact" && itemId !== "fork") {
          return { kind: "stay" };
        }

        taskContext = itemId;
        const outcome = await showMultiLineInput(ctx, {
          title: "Task",
          description: "Describe the task",
          signal,
        });
        if (outcome.kind === "submitted") {
          task = outcome.value;
          const summary = await showHandoffSummary(ctx, taskContext, task, signal);
          if (summary === "confirmed") {
            await onConfirm(taskContext, task);
            return { kind: "close" };
          }
          if (summary === "close") return { kind: "close" };
          return { kind: "stay" };
        }
        if (outcome.kind === "close") return { kind: "close" };
        return { kind: "stay" };
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
