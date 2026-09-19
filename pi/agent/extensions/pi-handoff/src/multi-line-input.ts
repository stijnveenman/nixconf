import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
  Editor,
  type EditorTheme,
  Key,
  matchesKey,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { type OutcomeType } from "./outcome.js";
import {
  formatInteractionHints,
  HorizontalRule,
  renderBoundedFrame,
  runCustomInteraction,
} from "@narumitw/pi-tui-kit";

export interface MultiLineInputOptions {
  title: string;
  description?: string;
  submitLabel?: string;
  cancelLabel?: string;
  initialValue?: string;
  signal?: AbortSignal;
}

export type MultiLineInputResult = OutcomeType<string>;

class PromptEditor extends Editor {
  constructor(
    tui: ConstructorParameters<typeof Editor>[0],
    theme: EditorTheme,
    private readonly promptPrefix: string,
  ) {
    super(tui, theme);
  }

  protected renderTopBorder(): string {
    return "";
  }

  protected renderBottomBorder(): string {
    return "";
  }

  render(width: number): string[] {
    return super
      .render(Math.max(1, width - 2))
      .filter(Boolean)
      .map((line) => `${this.promptPrefix}${line}`);
  }
}

export async function showMultiLineInput(
  ctx: ExtensionCommandContext,
  options: MultiLineInputOptions,
): Promise<MultiLineInputResult> {
  const result = await runCustomInteraction<MultiLineInputResult>(ctx, {
    signal: options.signal,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`Multiline input is unavailable in ${mode} mode.`, "warning");
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
      const editor = new PromptEditor(
        tui,
        editorTheme,
        theme.fg("dim", "> "),
      );
      if (options.initialValue) editor.setText(options.initialValue);
      editor.onSubmit = (value) => complete({ kind: "confirm", value });

      const rule = new HorizontalRule({
        ruleStyle: (text) => theme.fg("border", text),
        labelStyle: (text) => theme.fg("muted", text),
      });
      const hint = formatInteractionHints(keybindings, [
        { bindings: ["tui.input.newLine"], label: "newline" },
        { bindings: ["tui.input.submit"], label: options.submitLabel ?? "submit" },
        {
          bindings: ["tui.select.cancel"],
          excludeKeys: ["ctrl+c"],
          label: options.cancelLabel ?? "back",
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
            title: [theme.fg("accent", theme.bold(options.title))],
            context: options.description
              ? wrapTextWithAnsi(theme.fg("dim", options.description), safeWidth)
              : [],
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
