import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { registerDemos } from "./demo.js";
import { showHandoffMenu } from "./menu.js";

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
      await showHandoffMenu(ctx, async (_taskContext, task) => {
        pi.appendEntry("pi-handoff-task", { task });
      });
    },
  });

  registerDemos(pi);
}
