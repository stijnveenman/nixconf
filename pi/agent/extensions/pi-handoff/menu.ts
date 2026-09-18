import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
  Editor,
  type EditorTheme,
  Key,
  matchesKey,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import {
  defineMenu,
  formatInteractionHints,
  HorizontalRule,
  renderBoundedFrame,
  runCustomInteraction,
  runMenu,
} from "@narumitw/pi-tui-kit";

type TaskContext = "none" | "compact" | "fork";
type Screen = "context";
type Action = "editContext";
type EditTaskOutcome =
  | { kind: "submitted"; task: string }
  | { kind: "back" }
  | { kind: "close" }
  | { kind: "stale" }
  | { kind: "unsupported" }
  | { kind: "error" };

class PromptEditor extends Editor {
  constructor(
    tui: ConstructorParameters<typeof Editor>[0],
    theme: EditorTheme,
    private readonly promptPrefix: string,
  ) {
    super(tui, theme);
  }

  protected renderTopBorder(_width: number, _hiddenLineCount: number): string {
    return "";
  }

  protected renderBottomBorder(_width: number, _hiddenLineCount: number): string {
    return "";
  }

  render(width: number): string[] {
    return super
      .render(Math.max(1, width - 2))
      .filter(Boolean)
      .map((line) => `${this.promptPrefix}${line}`);
  }
}

export async function showEditTask(
  ctx: ExtensionCommandContext,
  signal: AbortSignal,
): Promise<EditTaskOutcome> {
  const result = await runCustomInteraction<EditTaskOutcome>(ctx, {
    signal,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`Task entry is unavailable in ${mode} mode.`, "warning");
    },
    create: ({ tui, theme, keybindings, complete }) => {
      const editorTheme: EditorTheme = {
        borderColor: (text) => theme.fg("accent", text),
        selectList: {
          selectedPrefix: (text) => theme.fg("accent", text),
          selectedText: (text) => theme.fg("accent", text),
          description: (text) => theme.fg("muted", text),
          scrollInfo: (text) => theme.fg("dim", text),
          noMatch: (text) => theme.fg("warning", text),
        },
      };
      const editor = new PromptEditor(tui, editorTheme, theme.fg("dim", "> "));
      editor.onSubmit = (task) => complete({ kind: "submitted", task });
      const rule = new HorizontalRule({
        ruleStyle: (text) => theme.fg("border", text),
      });
      const hint = formatInteractionHints(keybindings, [
        { bindings: ["tui.input.newLine"], label: "newline" },
        { bindings: ["tui.input.submit"], label: "submit" },
        {
          bindings: ["tui.select.cancel"],
          excludeKeys: ["ctrl+c"],
          label: "back",
        },
        { keys: ["ctrl+c"], label: "close" },
      ]);

      return {
        get focused() {
          return editor.focused;
        },
        set focused(value: boolean) {
          editor.focused = value;
        },
        render: (width: number) => {
          const safeWidth = Math.max(1, width);
          const content = [...editor.render(safeWidth)];
          return renderBoundedFrame({
            width: safeWidth,
            maxRows: Math.max(1, Math.floor(tui.terminal.rows) - 3),
            rule: rule.render(safeWidth)[0] ?? "",
            title: [theme.fg("accent", theme.bold("Task to hand off"))],
            context: wrapTextWithAnsi(
              theme.fg("dim", "Describe the task that should be handed off…"),
              safeWidth,
            ),
            content,
            hints: ["", theme.fg("dim", hint)],
            compactHint: theme.fg("dim", hint),
            priorityRows: [0],
          });
        },
        invalidate: () => editor.invalidate(),
        handleInput: (data: string) => {
          if (matchesKey(data, Key.ctrl("c"))) {
            complete({ kind: "close" });
          } else if (keybindings.matches(data, "tui.select.cancel")) {
            complete({ kind: "back" });
          } else {
            editor.handleInput(data);
          }
          tui.requestRender();
        },
      };
    },
  });

  if (result.kind === "completed") return result.value;
  if (result.kind === "stale") return { kind: "stale" };
  if (result.kind === "unsupported") return { kind: "unsupported" };
  return { kind: "error" };
}

export async function showHandoffMenu(ctx: ExtensionCommandContext) {
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
        const outcome = await showEditTask(ctx, signal);
        if (outcome.kind === "submitted") {
          task = outcome.task;
          return { kind: "close" };
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
