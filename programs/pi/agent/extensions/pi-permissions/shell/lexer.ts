export type Word = { value: string; expanded: boolean; raw: string };
export type Token = { kind: "word"; word: Word } | { kind: "op"; op: string };

export class ScanError extends Error {}

type Heredoc = { delimiter: string; stripTabs: boolean };
type OnSubstitution = (source: string) => void;

const OPERATORS = ["&&", "||", ";;&", ";;", ";&", "|&", "&>>", "&>", ">>", ">&", "<&", "<<<", "<<-", "<<", "<>", ">|", ">", "<", "|", "&", ";", "(", ")", "\n"];
const BLANKS = " \t\r";
const VARIABLE = /^[A-Za-z_][A-Za-z0-9_]*|^[0-9@*#?$!-]/;
const ANSI_ESCAPES: Record<string, string> = { n: "\n", t: "\t", r: "\r" };

export function tokenize(source: string, onSubstitution: OnSubstitution): Token[] {
  return new Lexer(source, onSubstitution).run();
}

class Lexer {
  private i = 0;
  private tokens: Token[] = [];
  private word: Word | null = null;
  private heredocs: Heredoc[] = [];

  private readonly src: string;
  private readonly onSubstitution: OnSubstitution;

  constructor(src: string, onSubstitution: OnSubstitution) {
    this.src = src;
    this.onSubstitution = onSubstitution;
  }

  run(): Token[] {
    while (this.i < this.src.length) this.step();
    if (this.heredocs.length) throw new ScanError("unterminated here-document");
    this.endWord();
    return this.tokens;
  }

  private step(): void {
    const c = this.src[this.i];
    if (c === "\\") return this.readEscape();
    if (c === "'") return this.readSingleQuoted();
    if (this.at("$'")) return this.readAnsiQuoted();
    if (c === '"') return this.readDoubleQuoted();
    if ((c === "$" || c === "`") && this.readExpansion()) return;
    if (this.at("<(") || this.at(">(")) return this.readProcessSubstitution();
    if (c === "#" && !this.word) return this.skipComment();
    if (BLANKS.includes(c)) {
      this.endWord();
      this.i++;
      return;
    }
    const op = OPERATORS.find((o) => this.at(o));
    if (op) return this.readOperator(op);
    this.append(c, c, this.i + 1);
  }

  private at(text: string): boolean {
    return this.src.startsWith(text, this.i);
  }

  private append(value: string, raw: string, next: number, expanded = false): void {
    this.word ??= { value: "", expanded: false, raw: "" };
    this.word.value += value;
    this.word.raw += raw;
    this.word.expanded ||= expanded;
    this.i = next;
  }

  private endWord(): void {
    if (this.word) this.tokens.push({ kind: "word", word: this.word });
    this.word = null;
  }

  private readEscape(): void {
    if (this.src[this.i + 1] === "\n") {
      this.i += 2;
      return;
    }
    this.append(this.src[this.i + 1] ?? "", this.src.slice(this.i, this.i + 2), this.i + 2);
  }

  private readSingleQuoted(): void {
    const end = this.src.indexOf("'", this.i + 1);
    if (end < 0) throw new ScanError("unterminated single quote");
    this.append(this.src.slice(this.i + 1, end), this.src.slice(this.i, end + 1), end + 1);
  }

  private readAnsiQuoted(): void {
    let j = this.i + 2;
    let value = "";
    while (j < this.src.length && this.src[j] !== "'") {
      if (this.src[j] === "\\" && j + 1 < this.src.length) {
        value += ANSI_ESCAPES[this.src[j + 1]] ?? this.src[j + 1];
        j += 2;
      } else value += this.src[j++];
    }
    if (j >= this.src.length) throw new ScanError("unterminated $'…' quote");
    this.append(value, this.src.slice(this.i, j + 1), j + 1);
  }

  private readDoubleQuoted(): void {
    let j = this.i + 1;
    let value = "";
    let expanded = false;
    while (j < this.src.length && this.src[j] !== '"') {
      const c = this.src[j];
      if (c === "\\" && '"\\$`\n'.includes(this.src[j + 1] ?? "")) {
        if (this.src[j + 1] !== "\n") value += this.src[j + 1];
        j += 2;
        continue;
      }
      const end = c === "$" || c === "`" ? skipExpansion(this.src, j, this.onSubstitution) : j;
      if (end > j) {
        expanded = true;
        value += this.src.slice(j, end);
        j = end;
      } else {
        value += c;
        j++;
      }
    }
    if (j >= this.src.length) throw new ScanError("unterminated double quote");
    this.append(value, this.src.slice(this.i, j + 1), j + 1, expanded);
  }

  private readExpansion(): boolean {
    const end = skipExpansion(this.src, this.i, this.onSubstitution);
    if (end === this.i) return false;
    const text = this.src.slice(this.i, end);
    this.append(text, text, end, true);
    return true;
  }

  private readProcessSubstitution(): void {
    const end = matchParen(this.src, this.i + 1);
    this.onSubstitution(this.src.slice(this.i + 2, end));
    const text = this.src.slice(this.i, end + 1);
    this.append(text, text, end + 1, true);
  }

  private skipComment(): void {
    while (this.i < this.src.length && this.src[this.i] !== "\n") this.i++;
  }

  private readOperator(op: string): void {
    // `2>&1`: a file descriptor glued to a redirection is not a word.
    if (/^[<>]/.test(op) && this.word && /^\d+$/.test(this.word.raw)) this.word = null;
    this.endWord();
    this.i += op.length;
    this.tokens.push({ kind: "op", op });
    if (op === "<<" || op === "<<-") this.readHeredocDelimiter(op === "<<-");
    if (op === "\n") this.skipHeredocBodies();
  }

  private readHeredocDelimiter(stripTabs: boolean): void {
    while (this.src[this.i] === " " || this.src[this.i] === "\t") this.i++;
    const start = this.i;
    while (this.i < this.src.length && !/[\s;&|<>()]/.test(this.src[this.i])) this.i++;
    const delimiter = this.src.slice(start, this.i).replace(/['"\\]/g, "");
    this.heredocs.push({ delimiter, stripTabs });
    this.tokens.push({ kind: "word", word: { value: delimiter, expanded: false, raw: delimiter } });
  }

  private skipHeredocBodies(): void {
    for (const doc of this.heredocs.splice(0)) {
      let line: string;
      do {
        if (this.i >= this.src.length) throw new ScanError("unterminated here-document");
        const newline = this.src.indexOf("\n", this.i);
        const end = newline < 0 ? this.src.length : newline;
        line = this.src.slice(this.i, end);
        this.i = end + 1;
        if (doc.stripTabs) line = line.replace(/^\t+/, "");
      } while (line !== doc.delimiter);
    }
  }
}

/**
 * Skips the `$…` or backtick expansion at `i`, reporting command substitutions
 * found in it. Returns the index after it, or `i` for a literal `$`.
 */
export function skipExpansion(src: string, i: number, onSubstitution: OnSubstitution): number {
  if (src[i] === "`") return skipBacktick(src, i, onSubstitution);
  if (src.startsWith("$((", i)) {
    const end = matchParen(src, i + 1);
    scanBody(src.slice(i + 3, end - 1), onSubstitution);
    return end + 1;
  }
  if (src.startsWith("$(", i)) {
    const end = matchParen(src, i + 1);
    onSubstitution(src.slice(i + 2, end));
    return end + 1;
  }
  if (src.startsWith("${", i)) {
    const end = src.indexOf("}", i + 2);
    if (end < 0) throw new ScanError("unterminated ${…}");
    scanBody(src.slice(i + 2, end), onSubstitution);
    return end + 1;
  }
  const name = VARIABLE.exec(src.slice(i + 1));
  return name ? i + 1 + name[0].length : i;
}

function skipBacktick(src: string, i: number, onSubstitution: OnSubstitution): number {
  let j = i + 1;
  let inner = "";
  while (j < src.length && src[j] !== "`") {
    if (src[j] === "\\" && j + 1 < src.length) j++;
    inner += src[j++];
  }
  if (j >= src.length) throw new ScanError("unterminated backtick");
  onSubstitution(inner);
  return j + 1;
}

/** Finds substitutions nested in `${…}` and `$((…))` bodies. */
function scanBody(body: string, onSubstitution: OnSubstitution): void {
  for (let k = 0; k < body.length; k++) {
    if (body[k] !== "$" && body[k] !== "`") continue;
    const end = skipExpansion(body, k, onSubstitution);
    if (end > k) k = end - 1;
  }
}

function skipQuoted(src: string, j: number): number {
  const quote = src[j];
  if (quote !== '"') return src.indexOf(quote, j + 1);
  for (j++; j < src.length && src[j] !== '"'; j++) if (src[j] === "\\") j++;
  return j;
}

/** Index of the `)` matching the `(` at `open`. */
function matchParen(src: string, open: number): number {
  let depth = 0;
  for (let j = open; j < src.length; j++) {
    const c = src[j];
    if (c === "\\") j++;
    else if (c === "'" || c === '"' || c === "`") {
      j = skipQuoted(src, j);
      if (j < 0) break;
    }
    else if (c === "(") depth++;
    else if (c === ")" && --depth === 0) return j;
  }
  throw new ScanError("unbalanced parentheses");
}
