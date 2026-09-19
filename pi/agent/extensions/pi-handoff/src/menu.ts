import type { ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { defineMenu, runMenu } from "@narumitw/pi-tui-kit";
import { buildCompaction, generateTaskRecommendations } from "./commands.js";
import { showMultiLineInput } from "./multi-line-input.js";
import { loadWorkmuxAgents } from "./workmux.js";

type TaskContext = "none" | "compact" | "fork";
type Screen =
  "context" | "recommendations" | "branchRecommendation" | "agentRecommendation";
type Action = "selectContext" | "updateBranch" | "selectAgent" | "confirm";

export interface HandoffState {
  taskContext: TaskContext;
  task: string;
  compaction?: string;
  branch?: string;
  agent?: string;
}

export async function showHandoffMenu(
  ctx: ExtensionCommandContext,
): Promise<Readonly<HandoffState> | undefined> {
  const agents = loadWorkmuxAgents();
  const state: HandoffState = {
    taskContext: "none",
    task: "",
  };
  let confirmed = false;
  const menu = defineMenu<HandoffState, Screen, Action>({
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
            description:
              "No task context, only user provided input will be passed to the new session.",
            details: ["Only the task text is passed to the new session."],
            searchText: "no none task only user input",
          },
          {
            id: "compact",
            label: "Compact",
            description:
              "Compact the current session, steering towards a task provided.",
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
      recommendations: () => ({
        kind: "actions",
        title: "Task recommendations",
        lines: ["Update a recommendation or confirm the handoff."],
        items:
          state.branch && state.agent
            ? [
                { id: "confirm", label: "Confirm", action: "confirm" },
                {
                  id: "agent",
                  label: "Agent",
                  description: state.agent,
                  action: "selectAgent",
                },
                {
                  id: "branch",
                  label: "Branch",
                  description: state.branch,
                  action: "updateBranch",
                },
              ]
            : [{ id: "close", label: "Close", close: true }],
        hint: "close",
      }),
      branchRecommendation: () => ({
        kind: "input",
        title: "Update branch recommendation",
        lines: ["Edit the branch name and press Enter to save."],
        initialValue: state.branch,
        action: "updateBranch",
        hint: "back",
      }),
      agentRecommendation: () => ({
        kind: "choice",
        title: "Update agent recommendation",
        lines: ["Choose a Workmux agent for the handoff."],
        items: Object.entries(agents).map(([name, agent]) => ({
          id: name,
          label: name,
          description: agent.description ?? "",
          searchText: `${name} ${agent.description ?? ""} ${agent.when ?? ""}`,
        })),
        action: "selectAgent",
        currentItemId: state.agent,
        enableSearch: true,
        hint: "back",
      }),
    },
    actions: {
      selectContext: async ({ ctx: actionCtx, state, itemId, signal }) => {
        if (itemId !== "none" && itemId !== "compact" && itemId !== "fork") {
          return { kind: "stay" };
        }

        state.taskContext = itemId;
        const taskOutcome = await showMultiLineInput(actionCtx, {
          title: "Task",
          description: "Describe the task",
          signal,
        });
        if (taskOutcome.kind === "close") return { kind: "close" };
        if (taskOutcome.kind !== "confirm") return { kind: "stay" };

        state.task = taskOutcome.value ?? "";
        state.compaction = undefined;

        if (state.taskContext === "compact") {
          const summary = await buildCompaction(actionCtx, state.task);
          if (summary === undefined) return { kind: "stay" };
          state.compaction = summary;
        }

        const recommendations = await generateTaskRecommendations(
          actionCtx,
          state.task,
          state.taskContext,
          state.compaction,
          agents,
        );
        if (!recommendations) return { kind: "stay" };
        state.branch = recommendations.branch;
        state.agent = recommendations.agent;

        return { kind: "to", screen: "recommendations" };
      },
      updateBranch: async ({ state, itemId, value }) => {
        if (itemId === "branch") return { kind: "to", screen: "branchRecommendation" };
        if (value !== undefined) {
          state.branch = value;
        }
        return { kind: "back" };
      },
      selectAgent: async ({ state, itemId }) => {
        if (itemId === "agent") {
          return { kind: "to", screen: "agentRecommendation" };
        }
        if (!agents[itemId]) {
          return { kind: "stay" };
        }
        state.agent = itemId;
        return { kind: "back" };
      },
      confirm: async () => {
        confirmed = true;
        return { kind: "close" };
      },
    },
  });

  await runMenu(ctx, menu, {
    getState: () => state,
    onUnsupportedMode: (_ctx, mode) => {
      ctx.ui.notify(`The handoff menu is unavailable in ${mode} mode.`, "warning");
    },
  });

  return confirmed ? state : undefined;
}
