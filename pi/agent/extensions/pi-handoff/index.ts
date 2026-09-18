import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { defineMenu, runMenu } from "@narumitw/pi-tui-kit";
import { registerDemos } from "./demo.js";

type Screen = "main";
type Action = "close";

const menu = defineMenu<undefined, Screen, Action>({
  start: "main",
  screens: {
    main: () => ({
      kind: "detail",
      title: "Pi handoff",
      lines: ["The handoff workflow is not implemented yet."],
      hint: "close",
    }),
  },
  actions: {
    close: async () => ({ kind: "close" }),
  },
});

export default function (pi: ExtensionAPI) {
  pi.registerCommand("handoff", {
    description: "Open the Pi handoff menu",
    handler: async (_args, ctx) => {
      await runMenu(ctx, menu, {
        getState: () => undefined,
        onUnsupportedMode: (_ctx, mode) => {
          ctx.ui.notify(`Pi handoff is unavailable in ${mode} mode.`, "warning");
        },
      });
    },
  });

  registerDemos(pi);
}
