/**
 * A small bash scanner that finds every command a command line would run.
 *
 * It splits `&&`, `||`, `;`, `|`, `&`, newlines, subshells, `$(…)`, backticks,
 * `<(…)`, control-flow bodies and function bodies, like opencode's scanner, and
 * additionally looks through wrappers (`sudo`, `env`, `xargs`, `timeout`,
 * `nohup`, `bash -c '…'`, `eval '…'`, `find -exec`, `watch`, `nix develop -c`,
 * …): the wrapper's own command line and the command it runs are both checked.
 *
 * Anything the scanner cannot see into (`$cmd …`, `python -c …`, a `bash -c`
 * script built from variables, unbalanced quotes) is reported as `opaque`, so
 * the caller can refuse to let a catch-all allow cover it.
 */

export type ShellCommand = {
  /** Words of the command, quotes removed, assignments and redirections dropped. */
  words: string[];
  /** `words` joined by spaces: the resource matched against `shell` rules. */
  text: string;
  /** The scanner could not tell what this command really runs. */
  opaque: boolean;
  /** Why it is opaque, for the prompt. */
  reason?: string;
  /** Text of the wrapper chain this command was found in, outermost first. */
  via: string[];
};

export type ScanResult = {
  commands: ShellCommand[];
  /** Directories the line `cd`s or `pushd`s into, as written. */
  cdTargets: string[];
};

type Word = { value: string; expanded: boolean; raw: string };
type Token = { kind: "word"; word: Word } | { kind: "op"; op: string };

class ScanError extends Error {}

const MAX_DEPTH = 8;

export function scan(source: string): ScanResult {
  const out: ScanResult = { commands: [], cdTargets: [] };
  try {
    scanInto(source, out, [], 0);
  } catch (error) {
    out.commands.push({
      words: [source.trim()],
      text: source.trim(),
      opaque: true,
      reason: error instanceof ScanError ? error.message : "could not parse the command",
      via: [],
    });
  }
  return out;
}

function scanInto(source: string, out: ScanResult, via: string[], depth: number): void {
  if (depth > MAX_DEPTH) throw new ScanError("commands nested too deeply");
  const tokens = tokenize(source, out, via, depth);
  for (const words of simpleCommands(tokens)) {
    handleCommand(words, out, via, depth);
  }
}

// ── Tokenizer ────────────────────────────────────────────────────────────────

const OPERATORS = ["&&", "||", ";;&", ";;", ";&", "|&", "&>>", "&>", ">>", ">&", "<&", "<<<", "<<-", "<<", "<>", ">|", ">", "<", "|", "&", ";", "(", ")", "\n"];

function tokenize(src: string, out: ScanResult, via: string[], depth: number): Token[] {
  const tokens: Token[] = [];
  const pendingHeredocs: { delim: string; strip: boolean }[] = [];
  let i = 0;
  let word: Word | null = null;

  const push = () => {
    if (word) tokens.push({ kind: "word", word });
    word = null;
  };
  const cur = (): Word => (word ??= { value: "", expanded: false, raw: "" });
  const nested = (inner: string) => scanInto(inner, out, via, depth + 1);

  while (i < src.length) {
    const c = src[i];

    if (c === "\\") {
      if (src[i + 1] === "\n") {
        i += 2;
        continue;
      }
      const w = cur();
      w.value += src[i + 1] ?? "";
      w.raw += src.slice(i, i + 2);
      i += 2;
      continue;
    }

    if (c === "'") {
      const end = src.indexOf("'", i + 1);
      if (end < 0) throw new ScanError("unterminated single quote");
      const w = cur();
      w.value += src.slice(i + 1, end);
      w.raw += src.slice(i, end + 1);
      i = end + 1;
      continue;
    }

    if (c === "$" && src[i + 1] === "'") {
      // ANSI-C quoting: keep escapes literal enough for matching.
      let j = i + 2;
      let value = "";
      while (j < src.length && src[j] !== "'") {
        if (src[j] === "\\" && j + 1 < src.length) {
          value += unescapeAnsi(src[j + 1]);
          j += 2;
        } else value += src[j++];
      }
      if (j >= src.length) throw new ScanError("unterminated $'…' quote");
      const w = cur();
      w.value += value;
      w.raw += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }

    if (c === '"') {
      let j = i + 1;
      const w = cur();
      while (j < src.length && src[j] !== '"') {
        const d = src[j];
        if (d === "\\" && j + 1 < src.length && '"\\$`\n'.includes(src[j + 1])) {
          if (src[j + 1] !== "\n") w.value += src[j + 1];
          j += 2;
        } else if (d === "$" || d === "`") {
          const end = expansion(src, j, nested);
          if (end > j) {
            w.expanded = true;
            w.value += src.slice(j, end);
            j = end;
          } else {
            w.value += d;
            j++;
          }
        } else {
          w.value += d;
          j++;
        }
      }
      if (j >= src.length) throw new ScanError("unterminated double quote");
      w.raw += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }

    if (c === "$" || c === "`") {
      const end = expansion(src, i, nested);
      if (end > i) {
        const w = cur();
        w.expanded = true;
        w.value += src.slice(i, end);
        w.raw += src.slice(i, end);
        i = end;
        continue;
      }
    }

    if ((c === "<" || c === ">") && src[i + 1] === "(") {
      const end = matchParen(src, i + 1);
      nested(src.slice(i + 2, end));
      const w = cur();
      w.expanded = true;
      w.value += src.slice(i, end + 1);
      w.raw += src.slice(i, end + 1);
      i = end + 1;
      continue;
    }

    if (c === "#" && !word) {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }

    if (c === " " || c === "\t" || c === "\r") {
      push();
      i++;
      continue;
    }

    const op = OPERATORS.find((o) => src.startsWith(o, i));
    if (op) {
      // `2>&1`, `2>file`: a file descriptor number glued to a redirection.
      if ((op.startsWith(">") || op.startsWith("<")) && word && /^\d+$/.test((word as Word).raw)) word = null;
      push();
      i += op.length;
      if (op === "<<" || op === "<<-") {
        // Read the delimiter word now so the body can be skipped at the newline.
        while (src[i] === " " || src[i] === "\t") i++;
        let j = i;
        while (j < src.length && !/[\s;&|<>()]/.test(src[j])) j++;
        const delim = src.slice(i, j).replace(/['"\\]/g, "");
        pendingHeredocs.push({ delim, strip: op === "<<-" });
        tokens.push({ kind: "op", op });
        tokens.push({ kind: "word", word: { value: delim, expanded: false, raw: delim } });
        i = j;
        continue;
      }
      tokens.push({ kind: "op", op });
      if (op === "\n" && pendingHeredocs.length) {
        for (const doc of pendingHeredocs.splice(0)) {
          for (;;) {
            if (i >= src.length) throw new ScanError("unterminated here-document");
            const nl = src.indexOf("\n", i);
            const line = src.slice(i, nl < 0 ? src.length : nl);
            i = nl < 0 ? src.length : nl + 1;
            if ((doc.strip ? line.replace(/^\t+/, "") : line) === doc.delim) break;
          }
        }
      }
      continue;
    }

    const w = cur();
    w.value += c;
    w.raw += c;
    i++;
  }
  if (pendingHeredocs.length) throw new ScanError("unterminated here-document");
  push();
  return tokens;
}

function unescapeAnsi(c: string): string {
  return ({ n: "\n", t: "\t", r: "\r", "\\": "\\", "'": "'", '"': '"' } as Record<string, string>)[c] ?? c;
}

/**
 * Handles `$…` or a backtick at `i`. Scans command substitutions recursively.
 * Returns the index after the expansion, or `i` when it is a literal `$`.
 */
function expansion(src: string, i: number, nested: (inner: string) => void): number {
  if (src[i] === "`") {
    let j = i + 1;
    let inner = "";
    while (j < src.length && src[j] !== "`") {
      if (src[j] === "\\" && j + 1 < src.length) {
        inner += src[j + 1];
        j += 2;
      } else inner += src[j++];
    }
    if (j >= src.length) throw new ScanError("unterminated backtick");
    nested(inner);
    return j + 1;
  }
  const next = src[i + 1];
  if (next === "(" && src[i + 2] === "(") {
    // Arithmetic `$(( … ))`: may still contain `$(…)`.
    const end = matchParen(src, i + 1);
    const body = src.slice(i + 3, end - 1);
    for (let k = 0; k < body.length; k++) {
      if (body[k] === "$" || body[k] === "`") {
        const e = expansion(body, k, nested);
        if (e > k) k = e - 1;
      }
    }
    return end + 1;
  }
  if (next === "(") {
    const end = matchParen(src, i + 1);
    nested(src.slice(i + 2, end));
    return end + 1;
  }
  if (next === "{") {
    const end = src.indexOf("}", i + 2);
    if (end < 0) throw new ScanError("unterminated ${…}");
    const body = src.slice(i + 2, end);
    // `${x:-$(cmd)}` and friends.
    for (let k = 0; k < body.length; k++) {
      if (body[k] === "$" || body[k] === "`") {
        const e = expansion(body, k, nested);
        if (e > k) k = e - 1;
      }
    }
    return end + 1;
  }
  const m = /^[A-Za-z_][A-Za-z0-9_]*|^[0-9@*#?$!-]/.exec(src.slice(i + 1));
  return m ? i + 1 + m[0].length : i;
}

/** Index of the `)` matching the `(` at `open`, aware of quotes and nesting. */
function matchParen(src: string, open: number): number {
  let depth = 0;
  for (let j = open; j < src.length; j++) {
    const c = src[j];
    if (c === "\\") {
      j++;
    } else if (c === "'") {
      j = src.indexOf("'", j + 1);
      if (j < 0) break;
    } else if (c === '"') {
      j++;
      while (j < src.length && src[j] !== '"') {
        if (src[j] === "\\") j++;
        j++;
      }
    } else if (c === "`") {
      j = src.indexOf("`", j + 1);
      if (j < 0) break;
    } else if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) return j;
    }
  }
  throw new ScanError("unbalanced parentheses");
}

// ── Grammar: token stream → simple commands ─────────────────────────────────

const SEPARATORS = new Set(["&&", "||", ";", "|", "&", "|&", "\n", "(", ")", ";;", ";&", ";;&"]);
const REDIRECTS = new Set([">", ">>", "<", "<>", ">|", "&>", "&>>", ">&", "<&", "<<<", "<<", "<<-"]);
const LEADING_KEYWORDS = new Set(["if", "then", "elif", "else", "fi", "do", "done", "while", "until", "!", "{", "}", "esac"]);

function simpleCommands(tokens: Token[]): Word[][] {
  const commands: Word[][] = [];
  let words: Word[] = [];
  let skipUntilSeparator = false; // `for x in …`, `select x in …`
  let caseState: "none" | "subject" | "pattern" = "none";
  let caseDepth = 0;

  const flush = () => {
    if (words.length) commands.push(words);
    words = [];
  };

  for (let k = 0; k < tokens.length; k++) {
    const t = tokens[k];
    if (t.kind === "op") {
      if (REDIRECTS.has(t.op)) {
        k++; // drop the redirection target
        continue;
      }
      if (t.op === ")" && caseState === "pattern") {
        caseState = "none";
        words = [];
        continue;
      }
      if ((t.op === ";;" || t.op === ";&" || t.op === ";;&") && caseDepth > 0) {
        flush();
        caseState = "pattern";
        continue;
      }
      if (t.op === "(" && caseState === "pattern") continue;
      if (SEPARATORS.has(t.op)) {
        // `name() { …; }`: a function definition, not a call.
        if (t.op === "(" && words.length === 1 && tokens[k + 1]?.kind === "op" && (tokens[k + 1] as { op: string }).op === ")") {
          words = [];
          k++;
          continue;
        }
        flush();
        if (t.op === ";" || t.op === "\n") skipUntilSeparator = false;
        continue;
      }
      continue;
    }

    const w = t.word;
    if (skipUntilSeparator) continue;
    if (caseState === "pattern") continue;
    if (caseState === "subject") {
      if (w.value === "in" && !w.expanded) caseState = "pattern";
      continue;
    }
    if (words.length === 0 && !w.expanded && w.raw === w.value) {
      if (LEADING_KEYWORDS.has(w.value)) {
        if (w.value === "esac") caseDepth = Math.max(0, caseDepth - 1);
        continue;
      }
      if (w.value === "for" || w.value === "select") {
        skipUntilSeparator = true;
        continue;
      }
      if (w.value === "case") {
        caseState = "subject";
        caseDepth++;
        continue;
      }
      if (w.value === "function") {
        k++; // function name
        continue;
      }
      if (w.value === "[[") {
        while (k < tokens.length && !(tokens[k].kind === "word" && (tokens[k] as { word: Word }).word.value === "]]")) k++;
        continue;
      }
    }
    if (words.length === 0 && caseDepth > 0 && w.value === "esac") {
      caseDepth--;
      continue;
    }
    // Leading `VAR=value` assignments are not part of the command name.
    if (words.length === 0 && /^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=/.test(w.raw)) continue;
    words.push(w);
  }
  flush();
  return commands;
}

// ── Wrappers ─────────────────────────────────────────────────────────────────

const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh", "mksh", "ash", "fish", "busybox"]);
const INTERPRETERS: Record<string, string[]> = {
  python: ["-c"],
  python2: ["-c"],
  python3: ["-c"],
  node: ["-e", "--eval", "-p", "--print"],
  deno: ["eval"],
  bun: ["-e", "--eval", "-p", "--print"],
  ruby: ["-e"],
  perl: ["-e", "-E"],
  php: ["-r"],
  lua: ["-e"],
  osascript: ["-e"],
  awk: [],
};

/** Options (by wrapper) that take a separate argument. */
const OPTION_ARGS: Record<string, Set<string>> = {
  sudo: new Set(["-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T", "-R", "--user", "--group", "--chdir", "--host", "--prompt", "--role", "--type", "--other-user", "--command-timeout", "--chroot"]),
  doas: new Set(["-u", "-C"]),
  env: new Set(["-u", "-C", "--unset", "--chdir"]),
  nice: new Set(["-n", "--adjustment"]),
  ionice: new Set(["-c", "-n", "-p", "-P", "-u", "--class", "--classdata"]),
  timeout: new Set(["-s", "-k", "--signal", "--kill-after"]),
  stdbuf: new Set(["-i", "-o", "-e"]),
  xargs: new Set(["-I", "-n", "-L", "-P", "-d", "-E", "-s", "-a", "--max-args", "--max-lines", "--max-procs", "--delimiter", "--eof", "--max-chars", "--arg-file", "--replace"]),
  watch: new Set(["-n", "-d", "--interval", "-q", "--equexit"]),
  exec: new Set(["-a"]),
  chrt: new Set(["-p"]),
  setpriv: new Set([]),
  flock: new Set(["-w", "-E", "--timeout", "--conflict-exit-code"]),
};

const SIMPLE_WRAPPERS = new Set(["nohup", "time", "setsid", "unbuffer", "caffeinate", "chronic", "nocorrect", "noglob", "builtin"]);

function handleCommand(words: Word[], out: ScanResult, via: string[], depth: number): void {
  if (words.length === 0) return;
  const text = words.map((w) => w.value).join(" ");
  const push = (opaque = false, reason?: string) =>
    out.commands.push({ words: words.map((w) => w.value), text, opaque, reason, via });
  const inner = (rest: Word[]) => handleCommand(rest, out, [...via, text], depth + 1);
  const script = (code: Word | undefined, what: string) => {
    if (!code) return;
    if (code.expanded) {
      out.commands.push({ words: [code.value], text: code.value, opaque: true, reason: `${what} script is built at run time`, via: [...via, text] });
      return;
    }
    scanInto(code.value, out, [...via, text], depth + 1);
  };

  if (depth > MAX_DEPTH) throw new ScanError("commands nested too deeply");

  const head = words[0];
  if (head.expanded) {
    push(true, "the command name is only known at run time");
    return;
  }
  const name = basename(head.value);

  if (name === "cd" || name === "pushd") {
    const target = words.slice(1).find((w) => !w.value.startsWith("-") || w.value === "-");
    if (target && target.value !== "-") out.cdTargets.push(target.value);
    push();
    return;
  }

  if (name === "command" && words[1]?.value.match(/^-[vV]/)) {
    push();
    return;
  }

  if (SIMPLE_WRAPPERS.has(name) || name === "command" || name === "exec" || name in OPTION_ARGS) {
    push();
    const rest = skipOptions(name, words.slice(1));
    if (rest === null) return;
    if ((name === "sudo" || name === "doas") && rest.length === 0 && words.some((w) => /^-[a-zA-Z]*[si]/.test(w.value))) {
      out.commands.push({ words: ["shell"], text: "shell", opaque: true, reason: `${name} opens an interactive root shell`, via: [...via, text] });
      return;
    }
    if (name === "env" && words.some((w) => w.value === "-S" || w.value.startsWith("--split-string"))) {
      out.commands.push({ words: [text], text, opaque: true, reason: "env -S splits a string into a command", via: [...via, text] });
      return;
    }
    if (name === "watch") {
      // watch joins its arguments and runs them through `sh -c`.
      if (rest.length) script({ value: rest.map((w) => w.value).join(" "), expanded: rest.some((w) => w.expanded), raw: "" }, "watch");
      return;
    }
    if (name === "xargs" && rest.length === 0) {
      inner([{ value: "echo", expanded: false, raw: "echo" }]);
      return;
    }
    if (name === "timeout") rest.shift(); // the duration
    if (name === "chrt" || name === "taskset") rest.shift(); // priority / mask
    if (name === "flock") rest.shift(); // the lock file
    if (rest.length) inner(rest);
    return;
  }

  if (name === "taskset") {
    push();
    const rest = words.slice(1).filter((w) => !w.value.startsWith("-"));
    rest.shift();
    if (rest.length) inner(rest);
    return;
  }

  if (SHELLS.has(name)) {
    push();
    let k = 1;
    if (name === "busybox") {
      if (words[1] && !SHELLS.has(basename(words[1].value))) {
        inner(words.slice(1));
        return;
      }
      k = 2;
    }
    for (; k < words.length; k++) {
      const v = words[k].value;
      if (v === "-c" || (/^-[a-zA-Z]+$/.test(v) && v.includes("c")) || v === "--command") {
        script(words[k + 1], name);
        return;
      }
      if (v === "-o" || v === "+o" || v === "--rcfile" || v === "--init-file") {
        k++;
        continue;
      }
      if (!v.startsWith("-") && !v.startsWith("+")) return; // `bash script.sh`: the script is not inspected
    }
    return;
  }

  if (name === "eval") {
    push();
    const rest = words.slice(1);
    script({ value: rest.map((w) => w.value).join(" "), expanded: rest.some((w) => w.expanded), raw: "" }, "eval");
    return;
  }

  if (name === "find" || name === "fd") {
    push();
    for (let k = 1; k < words.length; k++) {
      const v = words[k].value;
      if (name === "find" && ["-exec", "-execdir", "-ok", "-okdir"].includes(v)) {
        const end = words.findIndex((w, idx) => idx > k && (w.value === ";" || w.value === "+"));
        const cmd = words.slice(k + 1, end < 0 ? words.length : end);
        if (cmd.length) inner(cmd);
        k = end < 0 ? words.length : end;
      } else if (name === "fd" && (v === "-x" || v === "-X" || v === "--exec" || v === "--exec-batch")) {
        const cmd = words.slice(k + 1);
        if (cmd.length) inner(cmd);
        return;
      }
    }
    return;
  }

  if (name === "nix" && (words[1]?.value === "develop" || words[1]?.value === "shell")) {
    push();
    const idx = words.findIndex((w) => w.value === "-c" || w.value === "--command");
    if (idx > 0 && words[idx + 1]) inner(words.slice(idx + 1));
    return;
  }

  if (name === "nix-shell") {
    push();
    const idx = words.findIndex((w) => w.value === "--run" || w.value === "--command");
    if (idx > 0) script(words[idx + 1], "nix-shell");
    return;
  }

  if (name in INTERPRETERS) {
    const flags = INTERPRETERS[name];
    if (name === "awk") {
      const prog = words.slice(1).find((w) => !w.value.startsWith("-"));
      push(Boolean(prog && /system\s*\(|\|\s*"|getline/.test(prog.value)), "awk program runs shell commands");
      return;
    }
    const inline = words.slice(1).some((w) => flags.includes(w.value) || flags.some((f) => f.length === 2 && w.value.startsWith(f) && /^-[a-zA-Z]$/.test(f) && w.value.length > 2 && !w.value.startsWith("--")));
    push(inline, inline ? `${name} runs inline code` : undefined);
    return;
  }

  push();
}

/**
 * Skips a wrapper's options (and `VAR=value` for env/sudo). Returns the
 * remaining words, or null when the wrapper does not run a command.
 */
function skipOptions(name: string, words: Word[]): Word[] | null {
  const withArgs = OPTION_ARGS[name] ?? new Set<string>();
  let k = 0;
  for (; k < words.length; k++) {
    const v = words[k].value;
    if (v === "--") {
      k++;
      break;
    }
    if ((name === "env" || name === "sudo") && /^[A-Za-z_][A-Za-z0-9_]*=/.test(v)) continue;
    if (name === "nice" && /^-\d+$/.test(v)) continue;
    if (name === "command" && v === "-p") continue;
    if (!v.startsWith("-") || v === "-") break;
    if (withArgs.has(v)) k++;
    else if (name === "xargs" && v === "-i") continue;
  }
  return words.slice(k);
}

function basename(path: string): string {
  const i = path.lastIndexOf("/");
  return i < 0 ? path : path.slice(i + 1);
}
