import type { Token, Word } from "./lexer.ts";

const SEPARATORS = new Set(["&&", "||", ";", "|", "&", "|&", "\n", "(", ")", ";;", ";&", ";;&"]);
const CASE_SEPARATORS = new Set([";;", ";&", ";;&"]);
const REDIRECTS = new Set([">", ">>", "<", "<>", ">|", "&>", "&>>", ">&", "<&", "<<<", "<<", "<<-"]);
const SKIPPED_KEYWORDS = new Set(["if", "then", "elif", "else", "fi", "do", "done", "while", "until", "!", "{", "}"]);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=/;

/** Splits tokens into simple commands, dropping keywords, assignments and redirections. */
export function simpleCommands(tokens: Token[]): Word[][] {
  return new Grammar(tokens).run();
}

class Grammar {
  private k = 0;
  private commands: Word[][] = [];
  private words: Word[] = [];
  /** Inside `for x in …` or `select x in …` until the next `;` or newline. */
  private inLoopHeader = false;
  private caseState: "none" | "subject" | "pattern" = "none";
  private caseDepth = 0;

  private readonly tokens: Token[];

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  run(): Word[][] {
    for (; this.k < this.tokens.length; this.k++) {
      const token = this.tokens[this.k];
      if (token.kind === "op") this.onOperator(token.op);
      else this.onWord(token.word);
    }
    this.flush();
    return this.commands;
  }

  private flush(): void {
    if (this.words.length) this.commands.push(this.words);
    this.words = [];
  }

  private peekOperator(): string | undefined {
    const next = this.tokens[this.k + 1];
    return next?.kind === "op" ? next.op : undefined;
  }

  private onOperator(op: string): void {
    if (REDIRECTS.has(op)) {
      this.k++;
      return;
    }
    if (this.caseState === "pattern") {
      if (op === ")") {
        this.caseState = "none";
        this.words = [];
      }
      return;
    }
    if (CASE_SEPARATORS.has(op) && this.caseDepth > 0) {
      this.flush();
      this.caseState = "pattern";
      return;
    }
    if (!SEPARATORS.has(op)) return;
    if (op === "(" && this.words.length === 1 && this.peekOperator() === ")") {
      // `name() { …; }` defines a function; its body is scanned as usual.
      this.words = [];
      this.k++;
      return;
    }
    this.flush();
    if (op === ";" || op === "\n") this.inLoopHeader = false;
  }

  private onWord(word: Word): void {
    if (this.inLoopHeader) return;
    if (this.caseState === "pattern") {
      if (isPlain(word) && word.value === "esac") this.endCase();
      return;
    }
    if (this.caseState === "subject") {
      if (word.value === "in" && !word.expanded) this.caseState = "pattern";
      return;
    }
    if (this.words.length === 0) {
      if (isPlain(word) && this.onKeyword(word.value)) return;
      if (ASSIGNMENT.test(word.raw)) return;
    }
    this.words.push(word);
  }

  /** Handles a reserved word at command position; returns false for a normal word. */
  private onKeyword(keyword: string): boolean {
    if (SKIPPED_KEYWORDS.has(keyword)) return true;
    switch (keyword) {
      case "esac":
        this.endCase();
        return true;
      case "for":
      case "select":
        this.inLoopHeader = true;
        return true;
      case "case":
        this.caseState = "subject";
        this.caseDepth++;
        return true;
      case "function":
        this.k++;
        return true;
      case "[[":
        this.skipTestExpression();
        return true;
      default:
        return false;
    }
  }

  private endCase(): void {
    this.caseState = "none";
    this.caseDepth = Math.max(0, this.caseDepth - 1);
  }

  private skipTestExpression(): void {
    while (this.k < this.tokens.length) {
      const token = this.tokens[this.k];
      if (token.kind === "word" && token.word.value === "]]") return;
      this.k++;
    }
  }
}

function isPlain(word: Word): boolean {
  return !word.expanded && word.raw === word.value;
}
