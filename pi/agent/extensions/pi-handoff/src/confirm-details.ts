import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { type OutcomeType } from "./outcome.js";
import {
  formatInteractionHints,
  HorizontalRule,
  renderBoundedFrame,
  runCustomInteraction,
} from "@narumitw/pi-tui-kit";

export interface ConfirmDetailsOptions {
  title: string;
  context?: readonly string[];
  details: string;
  signal?: AbortSignal;
}

export type ConfirmDetailsResult = OutcomeType<undefined>;

export async function confirmDetails(
  ctx: ExtensionCommandContext,
  options: ConfirmDetailsOptions,
): Promise<ConfirmDetailsResult> {
  const result = await runCustomInteraction<ConfirmDetailsResult>(ctx, {
    signal: options.signal,
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
            title: [theme.fg("accent", theme.bold(options.title))],
            context: (options.context ?? []).map((line) => theme.fg("muted", line)),
            content: wrapTextWithAnsi(options.details, safeWidth),
            hints: ["", theme.fg("dim", hint)],
            compactHint: theme.fg("dim", hint),
            priorityRows: [0],
          });
        },
        invalidate() {},
        handleInput: (data: string) => {
          if (matchesKey(data, Key.ctrl("c"))) complete({ kind: "close" });
          else if (keybindings.matches(data, "tui.select.cancel")) complete({ kind: "back" });
          else if (keybindings.matches(data, "tui.input.submit")) complete({ kind: "confirm", value: undefined });
          tui.requestRender();
        },
      };
    },
  });

  return result.kind === "completed" ? result.value : { kind: "close" };
}
