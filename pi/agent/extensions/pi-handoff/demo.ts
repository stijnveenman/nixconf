import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import {
  defineMenu,
  HorizontalRule,
  renderBoundedFrame,
  runConfirmation,
  runDocumentReview,
  runMenu,
  runMultiSelect,
  runQuestionnaire,
  runSecretInput,
  runTask,
  runCustomInteraction,
} from "@narumitw/pi-tui-kit";
import { EditorStatusWidget } from "@narumitw/pi-tui-kit/editor-status-widget";
import { formatInteractionHints } from "@narumitw/pi-tui-kit/interaction-hints";
import {
  hardWrapTerminalDocument,
  sanitizeTerminalDocument,
} from "@narumitw/pi-tui-kit/terminal-document";

const demos: Record<string, string> = {
  "demo-horizontal-rule": "HorizontalRule: width-safe labelled dividers.",
  "demo-editor-status-widget": "EditorStatusWidget: passive status rows above the editor.",
  "demo-bounded-frame": "renderBoundedFrame: height-bounded, width-safe presentation.",
  "demo-menu": "defineMenu and runMenu: typed navigation with lifecycle handling.",
  "demo-task": "runTask: cancellable work with a Pi-styled loader.",
  "demo-confirmation": "runConfirmation: typed Confirmed, Back, Close, Stale, and Error results.",
  "demo-document-review": "runDocumentReview: searchable text, code, diff, and Markdown review.",
  "demo-multi-select": "runMultiSelect: private-ID selection with search and disabled rows.",
  "demo-live-choice": "runLiveChoice: cursor-driven preview with rollback ownership.",
  "demo-secret-input": "runSecretInput: masked single-secret input in TUI mode.",
  "demo-questionnaire": "runQuestionnaire: bounded choices, free-form answers, notes, and review.",
  "demo-model-selector": "runModelSelector: searchable model selection and save-default intent.",
  "demo-thinking-selector": "runThinkingSelector: searchable thinking-level selection.",
  "demo-interaction-hints": "formatInteractionHints: normalized, reachable keybinding hints.",
  "demo-terminal-document": "sanitizeTerminalDocument and hardWrapTerminalDocument: safe multiline display.",
  "demo-custom-interaction": "runCustomInteraction: owned cancellation and exactly-once disposal.",
  "demo-mermaid": "Mermaid Markdown preparation and synchronous message transformation.",
  "demo-actions": "actions screen: navigation, actions, disabled rows, and close.",
  "demo-detail": "detail screen: read-only wrapped content.",
  "demo-browse": "browse screen: searchable catalog and detail pages.",
  "demo-choice": "choice screen: confirmed static alternatives.",
  "demo-settings": "settings screen: searchable aligned values and serialized saves.",
  "demo-input": "input screen: editable values with validation-owned persistence.",
  "demo-review": "review screen: exact text, code, diff, or Markdown content.",
  "demo-multi-select-screen": "multiSelect screen: optimistic toggles and bulk actions.",
};

function registerDemo(pi: ExtensionAPI, command: string, description: string) {
  pi.registerCommand(command, {
    description: `Run the pi-tui-kit ${command.slice(5)} example`,
    handler: async (_args, ctx: ExtensionCommandContext) => {
      if (command === "demo-horizontal-rule" || command === "demo-bounded-frame") {
        await ctx.ui.custom<void>((_tui, theme, _keys, done) => {
          const rule = new HorizontalRule({
            label: command === "demo-horizontal-rule" ? "Preview" : undefined,
            ruleStyle: (text) => theme.fg("borderMuted", text),
            labelStyle: (text) => theme.fg("muted", text),
          });
          return {
            render: (width: number) => command === "demo-horizontal-rule"
              ? [...rule.render(width), theme.fg("text", "A width-safe horizontal rule demo"), ...rule.render(width)]
              : renderBoundedFrame({
                  width,
                  maxRows: 8,
                  rule: rule.render(width)[0] ?? "",
                  title: [theme.fg("accent", "Bounded frame")],
                  content: ["First setting", "Selected setting", "Saving…", "Extra content"],
                  hints: ["enter change • esc cancel"],
                  compactHint: "esc cancel",
                  priorityRows: [1, 2],
                  focusedRow: 1,
                }),
            invalidate() {},
            handleInput(data: string) {
              if (data === "\u001b" || data === "q") done();
            },
          };
        });
        return;
      }

      if (command === "demo-editor-status-widget") {
        ctx.ui.setWidget(
          "pi-handoff-demo",
          (_tui, theme) => new EditorStatusWidget({
            theme,
            renderBody: (width) => [theme.fg("muted", `Progress: rendering within ${width} columns`)],
          }),
          { placement: "aboveEditor" },
        );
        ctx.ui.notify("EditorStatusWidget installed. Run /clear-demo-widget to remove it.", "info");
        return;
      }

      if (command === "demo-task") {
        const result = await runTask(ctx, {
          label: "Running cancellable demo task…",
          task: async ({ signal }) => {
            await new Promise<void>((resolve, reject) => {
              const timer = setTimeout(resolve, 1200);
              signal.addEventListener("abort", () => {
                clearTimeout(timer);
                reject(signal.reason ?? new Error("aborted"));
              }, { once: true });
            });
            return "completed";
          },
        });
        ctx.ui.notify(`Task result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-confirmation") {
        const result = await runConfirmation(ctx, {
          title: "Run the handoff?",
          message: "This is a confirmation API demonstration.",
          confirmLabel: "Run",
          cancelLabel: "Not now",
        });
        ctx.ui.notify(`Confirmation result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-document-review" || command === "demo-review" || command === "demo-mermaid") {
        const result = await runDocumentReview(ctx, {
          title: command === "demo-mermaid" ? "Mermaid review" : "Generated handoff",
          content: command === "demo-mermaid"
            ? "# Handoff\n\n```mermaid\nflowchart LR\n  A[Current session] --> B[New session]\n```"
            : "diff --git a/handoff.txt b/handoff.txt\n+handoff preview\n+review before applying",
          format: command === "demo-mermaid" ? { kind: "markdown" } : { kind: "diff", filePath: "handoff.txt" },
          enableSearch: true,
        });
        ctx.ui.notify(`Review result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-multi-select" || command === "demo-multi-select-screen") {
        const result = await runMultiSelect(ctx, {
          title: "Handoff files",
          items: [
            { id: "summary", label: "Summary", selected: true, searchText: "session overview" },
            { id: "diff", label: "Diff", selected: true, searchText: "changed files" },
            { id: "transcript", label: "Transcript", selected: false, disabled: true, disabledReason: "Not available in this demo" },
          ],
          enableSearch: true,
          completionLabel: "Continue",
        });
        ctx.ui.notify(`Multi-select result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-questionnaire") {
        const result = await runQuestionnaire(ctx, {
          questions: [{
            id: "scope",
            header: "Scope",
            prompt: "What should the handoff include?",
            options: [
              { label: "Summary", description: "Current session summary" },
              { label: "Everything", description: "Summary, diff, and transcript" },
            ],
          }],
          allowNotes: true,
        });
        ctx.ui.notify(`Questionnaire result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-secret-input") {
        const result = await runSecretInput(ctx, { title: "Handoff passphrase", required: true });
        ctx.ui.notify(`Secret input result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-interaction-hints") {
        const hint = formatInteractionHints({ getKeys: () => [] }, [{ keys: ["e"], label: "edit" }, { keys: ["esc"], label: "close" }]);
        ctx.ui.notify(`Hints: ${hint}`, "info");
        return;
      }

      if (command === "demo-custom-interaction") {
        const result = await runCustomInteraction<{ kind: "back" | "close" }>(ctx, {
          create: ({ complete, signal }) => ({
            render: () => [signal.aborted ? "Closing…" : "Custom interaction demo", "Press Escape to go back."],
            invalidate() {},
            handleInput(data: string) {
              if (data === "\\u001b") complete({ kind: "back" });
            },
          }),
        });
        ctx.ui.notify(`Custom interaction result: ${result.kind}`, "info");
        return;
      }

      if (command === "demo-terminal-document") {
        const raw = "Handoff\\r\\n\\tready\\u001b[31m\\r\\nwith a long line that wraps";
        const safe = sanitizeTerminalDocument(raw);
        const lines = hardWrapTerminalDocument(safe, 32);
        ctx.ui.notify(lines.join(" | "), "info");
        return;
      }

      const screenKind = command.slice(5) as string;
      const screen = screenKind === "actions"
        ? { kind: "actions", title: "Actions", lines: ["Choose an action"], items: [{ id: "close", label: "Close", close: true }] }
        : screenKind === "choice"
          ? { kind: "choice", title: "Choice", items: [{ id: "safe", label: "Safe", description: "Recommended" }, { id: "fast", label: "Fast" }], action: "choose" }
          : screenKind === "settings"
            ? { kind: "settings", title: "Settings", items: [{ id: "mode", label: "Mode", currentValue: "Safe", values: ["Safe", "Fast"], action: "set" }] }
            : screenKind === "input"
              ? { kind: "input", title: "Input", placeholder: "Type a value", initialValue: "handoff", action: "submit" }
              : screenKind === "browse"
                ? { kind: "browse", title: "Browse", items: [{ id: "one", label: "One", details: ["A browsable item"] }, { id: "two", label: "Two", details: ["Another item"] }] }
                : screenKind === "review"
                  ? { kind: "review", title: "Review", content: "A reviewable handoff", format: { kind: "text" } }
                  : { kind: "detail", title: screenKind, lines: [description] };
      const demoMenu = defineMenu<any, "demo", string>({
        start: "demo",
        screens: { demo: () => screen as any },
        actions: {
          choose: async () => ({ kind: "stay" }),
          set: async () => ({ kind: "stay" }),
          submit: async () => ({ kind: "stay" }),
        },
      });
      await runMenu(ctx, demoMenu, {
        getState: () => undefined,
        onUnsupportedMode: (_ctx, mode) => ctx.ui.notify(`${command} is unavailable in ${mode} mode.`, "warning"),
      });
    },
  });
}

export function registerDemos(pi: ExtensionAPI) {
  for (const [command, description] of Object.entries(demos)) {
    registerDemo(pi, command, description);
  }

  pi.registerCommand("clear-demo-widget", {
    description: "Remove the pi-tui-kit editor widget demo",
    handler: async (_args, ctx) => {
      ctx.ui.setWidget("pi-handoff-demo", undefined);
      ctx.ui.notify("Demo widget removed.", "info");
    },
  });
}
