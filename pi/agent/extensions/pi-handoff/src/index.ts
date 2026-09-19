import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { runTask } from "@narumitw/pi-tui-kit";
import { Box, Text } from "@earendil-works/pi-tui";
import { registerDemos } from "./demo.js";
import { showHandoffMenu } from "./menu.js";
import { addWorkmuxAgent } from "./workmux.js";

export default function (pi: ExtensionAPI) {
  pi.registerEntryRenderer("pi-handoff-task", (entry, _options, theme) => {
    const data = entry.data as { task: string };
    const box = new Box(1, 0, (text) => theme.fg("muted", text));
    box.addChild(new Text(theme.fg("accent", `Task: ${data.task}`), 0, 0));
    return box;
  });

  pi.registerCommand("handoff", {
    description: "Hand off a task to another session",
    handler: async (_args, ctx) => {
      const state = await showHandoffMenu(ctx);
      if (!state?.agent || !state.branch) return;

      const agent = state.agent;
      const branch = state.branch;
      pi.appendEntry("pi-handoff-task", { task: state.task });
      const result = await runTask(ctx, {
        label: "Starting Workmux agent…",
        task: async () =>
          addWorkmuxAgent(
            agent,
            branch,
            state.task,
            state.compaction,
            state.taskContext === "fork"
              ? ctx.sessionManager.getSessionId()
              : undefined,
          ),
        onError: (_taskCtx, error) => {
          ctx.ui.notify(
            `Workmux failed: ${error instanceof Error ? error.message : String(error)}`,
            "error",
          );
        },
      });
      if (result.kind === "completed" && result.value) {
        pi.appendEntry("pi-handoff-task", { task: result.value });
      }
    },
  });

  registerDemos(pi);
}
