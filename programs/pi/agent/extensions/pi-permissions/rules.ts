/**
 * opencode v2-style rules: `{ action, resource, effect }`, evaluated against a
 * flat ordered list where the last matching rule wins and no match means ask.
 */

export type Effect = "allow" | "ask" | "deny";

export type Rule = {
  action: string;
  resource: string;
  effect: Effect;
  /** Where the rule came from, shown by /permissions and in block reasons. */
  source?: string;
};

export type Resource = {
  value: string;
  /** The scanner could not see into it: a catch-all allow does not cover it. */
  opaque?: boolean;
  reason?: string;
};

export type Decision = {
  effect: Effect;
  /** The rule that decided, when one matched. */
  rule?: Rule;
  /** The resource that decided (the first deny, or the asking ones). */
  resources: Resource[];
};

/** opencode v1 / pi tool names → v2 action names. */
const ACTION_ALIASES: Record<string, string> = {
  bash: "shell",
  task: "subagent",
  write: "edit",
  patch: "edit",
  multiedit: "edit",
  find: "glob",
  ls: "list",
  codemode: "execute",
};

export function normalizeAction(action: string): string {
  return ACTION_ALIASES[action] ?? action;
}

const EFFECTS = new Set<Effect>(["allow", "ask", "deny"]);

export function isEffect(value: unknown): value is Effect {
  return typeof value === "string" && EFFECTS.has(value as Effect);
}

/**
 * Accepts a v2 list (`[{action, resource, effect}]`) or a v1 object
 * (`{ bash: { "git *": "allow" }, edit: "ask" }` or a bare `"ask"`), in order.
 */
export function parseRules(value: unknown, source: string, errors: string[] = []): Rule[] {
  if (value == null) return [];
  if (isEffect(value)) return [{ action: "*", resource: "*", effect: value, source }];
  if (Array.isArray(value)) {
    const rules: Rule[] = [];
    value.forEach((entry, idx) => {
      if (typeof entry !== "object" || entry === null) {
        errors.push(`${source}: rule ${idx} is not an object`);
        return;
      }
      const { action, resource, effect } = entry as Record<string, unknown>;
      const eff = effect ?? (entry as Record<string, unknown>).permission;
      if (typeof action !== "string" || !isEffect(eff)) {
        errors.push(`${source}: rule ${idx} needs a string "action" and an "effect" of allow, ask or deny`);
        return;
      }
      rules.push({
        action: normalizeAction(action),
        resource: typeof resource === "string" ? resource : "*",
        effect: eff,
        source,
      });
    });
    return rules;
  }
  if (typeof value === "object") {
    const rules: Rule[] = [];
    for (const [action, spec] of Object.entries(value as Record<string, unknown>)) {
      if (isEffect(spec)) {
        rules.push({ action: normalizeAction(action), resource: "*", effect: spec, source });
      } else if (spec && typeof spec === "object" && !Array.isArray(spec)) {
        for (const [resource, effect] of Object.entries(spec as Record<string, unknown>)) {
          if (isEffect(effect)) rules.push({ action: normalizeAction(action), resource, effect, source });
          else errors.push(`${source}: ${action}.${resource} must be allow, ask or deny`);
        }
      } else errors.push(`${source}: ${action} must be allow, ask, deny or an object of patterns`);
    }
    return rules;
  }
  errors.push(`${source}: permissions must be a list of rules or an object`);
  return [];
}

const regexCache = new Map<string, RegExp>();

/**
 * opencode's wildcard: `*` matches any run of characters (including `/`), `?`
 * one character, the rest is literal and the whole value must match. A pattern
 * ending in ` *` or `/*` also matches the value without that suffix, so
 * `git status *` covers `git status` and `/tmp/*` covers `/tmp`.
 */
export function wildcardMatch(pattern: string, value: string): boolean {
  if (pattern === "*") return true;
  let re = regexCache.get(pattern);
  if (!re) {
    const toRegex = (p: string) => {
      let body = "";
      for (const ch of p) {
        if (ch === "*") body += "[\\s\\S]*";
        else if (ch === "?") body += "[\\s\\S]";
        else body += ch.replace(/[.+^${}()|[\]\\]/g, "\\$&");
      }
      return body;
    };
    const suffix = pattern.endsWith(" *") ? " " : pattern.endsWith("/*") && pattern.length > 2 ? "/" : null;
    const body = suffix ? `${toRegex(pattern.slice(0, -2))}(?:${suffix === "/" ? "/" : " "}[\\s\\S]*)?` : toRegex(pattern);
    re = new RegExp(`^${body}$`);
    regexCache.set(pattern, re);
  }
  return re.test(value);
}

/** The last rule matching `action` and `resource`, or undefined. */
export function findRule(rules: Rule[], action: string, resource: string): Rule | undefined {
  for (let i = rules.length - 1; i >= 0; i--) {
    const rule = rules[i];
    if (wildcardMatch(rule.action, action) && wildcardMatch(rule.resource, resource)) return rule;
  }
  return undefined;
}

const RANK: Record<Effect, number> = { allow: 0, ask: 1, deny: 2 };

/**
 * opencode's `Permission.assert`, plus the opaque floor:
 *   1. Any resource denied by the configured rules → deny. Saved approvals are
 *      not consulted, so they can never override a configured deny.
 *   2. Evaluate again with approvals appended. Any ask → ask, else allow.
 *   3. An opaque resource allowed only by a catch-all (`*`) rule, or by no rule,
 *      asks instead: the catch-all was not written with it in mind.
 */
export function decide(action: string, resources: Resource[], rules: Rule[], approvals: Rule[]): Decision {
  const list = resources.length ? resources : [{ value: "*" }];
  for (const res of list) {
    const rule = findRule(rules, action, res.value);
    if (rule?.effect === "deny") return { effect: "deny", rule, resources: [res] };
  }
  const all = approvals.length ? [...rules, ...approvals] : rules;
  const asking: Resource[] = [];
  let decidingRule: Rule | undefined;
  for (const res of list) {
    const rule = findRule(all, action, res.value);
    let effect: Effect = rule?.effect ?? "ask";
    if (effect === "allow" && res.opaque && (!rule || rule.resource === "*")) effect = "ask";
    if (effect === "ask") {
      asking.push(res);
      decidingRule ??= rule;
    }
  }
  if (asking.length) return { effect: "ask", rule: decidingRule, resources: asking };
  return { effect: "allow", resources: list };
}

export function stricter(a: Effect, b: Effect): Effect {
  return RANK[a] >= RANK[b] ? a : b;
}

/**
 * Whether every resource of `action` is denied: true when the last rule that
 * matches the action with resource `*` is a deny, and no later rule for the
 * action could allow or ask. Used to hide tools, like opencode does.
 */
export function isFullyDenied(rules: Rule[], action: string): boolean {
  let denied = false;
  for (const rule of rules) {
    if (!wildcardMatch(rule.action, action)) continue;
    if (rule.resource === "*") denied = rule.effect === "deny";
    else if (rule.effect !== "deny") denied = false;
  }
  return denied;
}

/** opencode's base policy for every agent. */
export const DEFAULT_RULES: Rule[] = [
  { action: "*", resource: "*", effect: "allow", source: "default" },
  { action: "read", resource: "*.env", effect: "ask", source: "default" },
  { action: "read", resource: "*.env.*", effect: "ask", source: "default" },
  { action: "read", resource: "*.env.example", effect: "allow", source: "default" },
];

/**
 * How many words of a command make up its "always allow" prefix, like
 * opencode's arity table: `git status --short` → `git status *`.
 */
const ARITY: Record<string, number> = {
  git: 2,
  npm: 2,
  pnpm: 2,
  yarn: 2,
  bun: 2,
  npx: 2,
  bunx: 2,
  cargo: 2,
  go: 2,
  docker: 2,
  podman: 2,
  kubectl: 2,
  helm: 2,
  terraform: 2,
  gh: 3,
  nix: 2,
  "nix-env": 2,
  nh: 3,
  systemctl: 2,
  brew: 2,
  apt: 2,
  "apt-get": 2,
  pip: 2,
  uv: 2,
  poetry: 2,
  make: 2,
  just: 2,
  dotnet: 2,
  mvn: 2,
  gradle: 2,
  aws: 3,
  gcloud: 3,
  az: 3,
  acli: 4,
  td: 2,
  herdr: 3,
  wt: 2,
};

export function alwaysPattern(words: string[]): string {
  if (!words.length) return "*";
  const arity = ARITY[words[0]] ?? 1;
  const prefix: string[] = [];
  for (const word of words.slice(0, arity)) {
    if (word.startsWith("-") && prefix.length) break;
    prefix.push(word);
  }
  return `${prefix.join(" ")} *`;
}
