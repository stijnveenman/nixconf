import type { ExtensionUIContext } from "@earendil-works/pi-coding-agent";
import type { AskAnswer, AskRequest } from "./registry.ts";

export async function showPrompt(ui: ExtensionUIContext, request: AskRequest): Promise<AskAnswer> {
  const patterns = [...new Set(request.patterns)].map((p) => `${request.action} ${p}`).join(", ");
  const title = [`${request.who} needs permission for ${request.action}:`, ...request.lines.map((line) => `  ${line}`)].join("\n");
  const answers: [string, () => Promise<AskAnswer> | AskAnswer][] = [
    ["Allow once", () => ({ kind: "once" })],
    [`Always allow this session: ${patterns}`, () => ({ kind: "session" })],
    ["Deny", () => ({ kind: "deny" })],
    ["Deny with feedback…", () => askFeedback(ui)],
  ];
  const choice = await ui.select(title, answers.map(([label]) => label));
  const answer = answers.find(([label]) => label === choice)?.[1];
  return answer ? answer() : { kind: "deny" };
}

async function askFeedback(ui: ExtensionUIContext): Promise<AskAnswer> {
  const feedback = await ui.input("Tell the agent why (or what to do instead)", "");
  return { kind: "deny", feedback: feedback?.trim() || undefined };
}

/** Shows one prompt at a time; a queued request is skipped when an earlier answer already covers it. */
export function promptQueue(show: (request: AskRequest) => Promise<AskAnswer>): (request: AskRequest) => Promise<AskAnswer> {
  let tail: Promise<unknown> = Promise.resolve();
  return (request) => {
    const answer = tail.then(() => (request.stillNeeded() ? show(request) : ({ kind: "once" } as const)));
    tail = answer.catch(() => undefined);
    return answer;
  };
}
