/**
 * Finds every command a bash command line would run, including those behind
 * wrappers like `sudo`, `xargs` or `bash -c`. Commands it cannot see into are
 * marked `opaque` so a catch-all allow does not cover them.
 */

import { basename, HANDLERS, runsCommandOnly } from "./commands.ts";
import { simpleCommands } from "./grammar.ts";
import { ScanError, tokenize, type Word } from "./lexer.ts";

export type ShellCommand = {
  /** Quotes removed, assignments and redirections dropped. */
  words: string[];
  /** `words` joined by spaces: the resource matched against `shell` rules. */
  text: string;
  opaque: boolean;
  reason?: string;
  /** Wrapper command lines this command was found in, outermost first. */
  via: string[];
};

export type ScanResult = {
  commands: ShellCommand[];
  /** Directories the line `cd`s or `pushd`s into, as written. */
  cdTargets: string[];
};

const MAX_DEPTH = 8;

export function scan(source: string): ScanResult {
  const result: ScanResult = { commands: [], cdTargets: [] };
  try {
    new Scanner(result, [], 0).scanSource(source);
  } catch (error) {
    const text = source.trim();
    const reason = error instanceof ScanError ? error.message : "could not parse the command";
    result.commands.push({ words: [text], text, opaque: true, reason, via: [] });
  }
  return result;
}

class Scanner {
  readonly result: ScanResult;
  readonly via: string[];
  readonly depth: number;

  constructor(result: ScanResult, via: string[], depth: number) {
    if (depth > MAX_DEPTH) throw new ScanError("commands nested too deeply");
    this.result = result;
    this.via = via;
    this.depth = depth;
  }

  nested(wrapper?: string): Scanner {
    return new Scanner(this.result, wrapper ? [...this.via, wrapper] : this.via, this.depth + 1);
  }

  scanSource(source: string): void {
    const tokens = tokenize(source, (inner) => this.nested().scanSource(inner));
    for (const words of simpleCommands(tokens)) this.scanCommand(words);
  }

  scanCommand(words: Word[]): void {
    if (!words.length) return;
    const command = new Command(words, this);
    if (words[0].expanded) {
      command.emit(true, "the command name is only known at run time");
      return;
    }
    (HANDLERS[command.name] ?? runsCommandOnly)(command);
  }
}

/** A simple command being scanned, with helpers for the wrapper handlers. */
export class Command {
  readonly text: string;
  readonly name: string;
  readonly args: Word[];
  readonly words: Word[];
  private readonly scanner: Scanner;

  constructor(words: Word[], scanner: Scanner) {
    this.words = words;
    this.scanner = scanner;
    this.text = words.map((w) => w.value).join(" ");
    this.name = basename(words[0].value);
    this.args = words.slice(1);
  }

  emit(opaque = false, reason?: string): void {
    const words = this.words.map((w) => w.value);
    this.scanner.result.commands.push({ words, text: this.text, opaque, reason: opaque ? reason : undefined, via: this.scanner.via });
  }

  /** Reports something this command runs that cannot be inspected. */
  emitOpaque(text: string, reason: string): void {
    this.scanner.result.commands.push({ words: [text], text, opaque: true, reason, via: [...this.scanner.via, this.text] });
  }

  addCdTarget(target: string): void {
    this.scanner.result.cdTargets.push(target);
  }

  runs(words: Word[]): void {
    if (words.length) this.scanner.nested(this.text).scanCommand(words);
  }

  runsScript(script: Word | undefined, what: string): void {
    if (!script) return;
    if (script.expanded) this.emitOpaque(script.value, `${what} script is built at run time`);
    else this.scanner.nested(this.text).scanSource(script.value);
  }

  /** Runs `words` joined into one script, like `eval` and `watch` do. */
  runsJoined(words: Word[], what: string): void {
    if (!words.length) return;
    const value = words.map((w) => w.value).join(" ");
    this.runsScript({ value, raw: value, expanded: words.some((w) => w.expanded) }, what);
  }
}
