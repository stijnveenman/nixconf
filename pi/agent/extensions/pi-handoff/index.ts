import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerDemos } from "./demo.js";
import { showHandoffMenu } from "./menu.js";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("handoff", {
    description: "Hand off a task to another session",
    handler: async (_args, ctx) => {
      await showHandoffMenu(ctx);
    },
  });

  registerDemos(pi);
}
