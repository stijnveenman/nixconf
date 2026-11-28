import type { Word } from "./lexer.ts";
import type { Command } from "./scan.ts";

type Handler = (command: Command) => void;

export function runsCommandOnly(command: Command): void {
  command.emit();
}

export function basename(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

/**
 * Skips leading options, and `VAR=value` where the wrapper accepts them.
 * `withArgument` lists the options that take a separate argument.
 */
function skipOptions(words: Word[], withArgument: string[] = [], allowAssignments = false): Word[] {
  let k = 0;
  while (k < words.length) {
    const value = words[k].value;
    if (value === "--") return words.slice(k + 1);
    const isAssignment = allowAssignments && /^[A-Za-z_][A-Za-z0-9_]*=/.test(value);
    if (!isAssignment && (!value.startsWith("-") || value === "-")) break;
    k += withArgument.includes(value) ? 2 : 1;
  }
  return words.slice(k);
}

/** A wrapper that runs the command after its options and `operands` fixed arguments. */
function wrapper(withArgument: string[] = [], operands = 0, allowAssignments = false): Handler {
  return (command) => {
    command.emit();
    command.runs(skipOptions(command.args, withArgument, allowAssignments).slice(operands));
  };
}

function changeDirectory(command: Command): void {
  command.emit();
  const target = command.args.find((w) => !w.value.startsWith("-"));
  if (target) command.addCdTarget(target.value);
}

function commandBuiltin(command: Command): void {
  if (/^-[vV]/.test(command.args[0]?.value ?? "")) command.emit();
  else wrapper()(command);
}

const SUDO_OPTIONS = ["-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T", "-R", "--user", "--group", "--chdir", "--host", "--prompt", "--role", "--type", "--other-user", "--command-timeout", "--chroot"];

function elevate(withArgument: string[]): Handler {
  return (command) => {
    command.emit();
    const rest = skipOptions(command.args, withArgument, true);
    const opensShell = command.args.some((w) => /^-[a-zA-Z]*[si]/.test(w.value));
    if (!rest.length && opensShell) command.emitOpaque("shell", `${command.name} opens an interactive root shell`);
    else command.runs(rest);
  };
}

function env(command: Command): void {
  if (command.args.some((w) => w.value === "-S" || w.value.startsWith("--split-string"))) {
    command.emit();
    command.emitOpaque(command.text, "env -S splits a string into a command");
    return;
  }
  wrapper(["-u", "-C", "--unset", "--chdir"], 0, true)(command);
}

const XARGS_OPTIONS = ["-I", "-n", "-L", "-P", "-d", "-E", "-s", "-a", "--max-args", "--max-lines", "--max-procs", "--delimiter", "--eof", "--max-chars", "--arg-file", "--replace"];

function xargs(command: Command): void {
  command.emit();
  const rest = skipOptions(command.args, XARGS_OPTIONS);
  command.runs(rest.length ? rest : [{ value: "echo", raw: "echo", expanded: false }]);
}

function watch(command: Command): void {
  command.emit();
  command.runsJoined(skipOptions(command.args, ["-n", "-d", "--interval", "-q", "--equexit"]), "watch");
}

function taskset(command: Command): void {
  command.emit();
  command.runs(command.args.filter((w) => !w.value.startsWith("-")).slice(1));
}

function evalBuiltin(command: Command): void {
  command.emit();
  command.runsJoined(command.args, "eval");
}

function shell(command: Command): void {
  command.emit();
  const args = command.args;
  for (let k = 0; k < args.length; k++) {
    const value = args[k].value;
    if (value === "--command" || /^-[a-zA-Z]*c[a-zA-Z]*$/.test(value)) return command.runsScript(args[k + 1], command.name);
    if (["-o", "+o", "--rcfile", "--init-file"].includes(value)) k++;
    else if (!/^[-+]/.test(value)) return;
  }
}

function busybox(command: Command): void {
  const applet = command.args[0];
  if (applet && SHELLS.includes(basename(applet.value))) return shell(command);
  command.emit();
  command.runs(command.args);
}

const FIND_EXEC = ["-exec", "-execdir", "-ok", "-okdir"];

function find(command: Command): void {
  command.emit();
  const args = command.args;
  for (let k = 0; k < args.length; k++) {
    if (!FIND_EXEC.includes(args[k].value)) continue;
    const end = args.findIndex((w, i) => i > k && (w.value === ";" || w.value === "+"));
    command.runs(args.slice(k + 1, end < 0 ? undefined : end));
    if (end < 0) return;
    k = end;
  }
}

function fd(command: Command): void {
  command.emit();
  const start = command.args.findIndex((w) => ["-x", "-X", "--exec", "--exec-batch"].includes(w.value));
  if (start >= 0) command.runs(command.args.slice(start + 1));
}

function nix(command: Command): void {
  command.emit();
  if (!["develop", "shell"].includes(command.args[0]?.value ?? "")) return;
  const start = command.args.findIndex((w) => w.value === "-c" || w.value === "--command");
  if (start >= 0) command.runs(command.args.slice(start + 1));
}

function nixShell(command: Command): void {
  command.emit();
  const start = command.args.findIndex((w) => w.value === "--run" || w.value === "--command");
  if (start >= 0) command.runsScript(command.args[start + 1], "nix-shell");
}

function inlineCode(flags: string[]): Handler {
  return (command) => {
    const inline = command.args.some((w) => flags.includes(w.value) || flags.some((f) => /^-[a-zA-Z]$/.test(f) && w.value.startsWith(f)));
    command.emit(inline, `${command.name} runs inline code`);
  };
}

function awk(command: Command): void {
  const program = command.args.find((w) => !w.value.startsWith("-"));
  command.emit(/system\s*\(|\|\s*"|getline/.test(program?.value ?? ""), "awk program runs shell commands");
}

const SHELLS = ["bash", "sh", "zsh", "dash", "ksh", "mksh", "ash", "fish"];
const PLAIN_WRAPPERS = ["nohup", "time", "setsid", "unbuffer", "caffeinate", "chronic", "nocorrect", "noglob", "builtin"];

export const HANDLERS: Record<string, Handler> = {
  ...Object.fromEntries(SHELLS.map((name) => [name, shell])),
  ...Object.fromEntries(PLAIN_WRAPPERS.map((name) => [name, wrapper()])),
  cd: changeDirectory,
  pushd: changeDirectory,
  command: commandBuiltin,
  exec: wrapper(["-a"]),
  sudo: elevate(SUDO_OPTIONS),
  doas: elevate(["-u", "-C"]),
  env,
  nice: wrapper(["-n", "--adjustment"]),
  ionice: wrapper(["-c", "-n", "-p", "-P", "-u", "--class", "--classdata"]),
  timeout: wrapper(["-s", "-k", "--signal", "--kill-after"], 1),
  stdbuf: wrapper(["-i", "-o", "-e"]),
  chrt: wrapper(["-p"], 1),
  flock: wrapper(["-w", "-E", "--timeout", "--conflict-exit-code"], 1),
  taskset,
  xargs,
  watch,
  eval: evalBuiltin,
  busybox,
  find,
  fd,
  nix,
  "nix-shell": nixShell,
  awk,
  python: inlineCode(["-c"]),
  python2: inlineCode(["-c"]),
  python3: inlineCode(["-c"]),
  node: inlineCode(["-e", "--eval", "-p", "--print"]),
  bun: inlineCode(["-e", "--eval", "-p", "--print"]),
  deno: inlineCode(["eval"]),
  ruby: inlineCode(["-e"]),
  perl: inlineCode(["-e", "-E"]),
  php: inlineCode(["-r"]),
  lua: inlineCode(["-e"]),
  osascript: inlineCode(["-e"]),
};
