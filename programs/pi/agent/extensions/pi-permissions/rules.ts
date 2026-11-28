export type Effect = "allow" | "ask" | "deny";

export type Rule = {
  action: string;
  resource: string;
  effect: Effect;
  /** Where the rule came from, for /permissions and block reasons. */
  source?: string;
};

export type Resource = {
  value: string;
  /** The shell scanner could not see what it runs. */
  opaque?: boolean;
  reason?: string;
};

export type Decision = {
  effect: Effect;
  rule?: Rule;
  /** The denied resource, or every resource that still asks. */
  resources: Resource[];
};

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

export function isEffect(value: unknown): value is Effect {
  return value === "allow" || value === "ask" || value === "deny";
}

export const DEFAULT_RULES: Rule[] = [
  { action: "*", resource: "*", effect: "allow", source: "default" },
  { action: "read", resource: "*.env", effect: "ask", source: "default" },
  { action: "read", resource: "*.env.*", effect: "ask", source: "default" },
  { action: "read", resource: "*.env.example", effect: "allow", source: "default" },
];

const regexCache = new Map<string, RegExp>();

/**
 * opencode's wildcard: `*` matches anything including `/`, `?` one character,
 * and the whole value must match. A trailing ` *` or `/*` is optional, so
 * `git status *` covers `git status` and `/tmp/*` covers `/tmp`.
 */
export function wildcardMatch(pattern: string, value: string): boolean {
  if (pattern === "*") return true;
  let re = regexCache.get(pattern);
  if (!re) {
    re = wildcardRegex(pattern);
    regexCache.set(pattern, re);
  }
  return re.test(value);
}

function wildcardRegex(pattern: string): RegExp {
  const optionalTail = pattern.length > 2 && (pattern.endsWith(" *") || pattern.endsWith("/*"));
  if (!optionalTail) return new RegExp(`^${globBody(pattern)}$`);
  const separator = pattern.at(-2) === "/" ? "/" : " ";
  return new RegExp(`^${globBody(pattern.slice(0, -2))}(?:${separator}[\\s\\S]*)?$`);
}

function globBody(pattern: string): string {
  return [...pattern]
    .map((ch) => (ch === "*" ? "[\\s\\S]*" : ch === "?" ? "[\\s\\S]" : ch.replace(/[.+^${}()|[\]\\]/g, "\\$&")))
    .join("");
}

/** The last rule matching both `action` and `resource`. */
export function findRule(rules: Rule[], action: string, resource: string): Rule | undefined {
  return rules.findLast((rule) => wildcardMatch(rule.action, action) && wildcardMatch(rule.resource, resource));
}

/**
 * opencode's evaluation: a deny from the configured rules wins before
 * approvals are consulted, so an approval can never override a deny. Then any
 * resource that still asks makes the call ask.
 */
export function decide(action: string, resources: Resource[], rules: Rule[], approvals: Rule[]): Decision {
  const list = resources.length ? resources : [{ value: "*" }];
  for (const resource of list) {
    const rule = findRule(rules, action, resource.value);
    if (rule?.effect === "deny") return { effect: "deny", rule, resources: [resource] };
  }
  const withApprovals = [...rules, ...approvals];
  const asking = list
    .map((resource) => ({ resource, rule: findRule(withApprovals, action, resource.value) }))
    .filter(({ resource, rule }) => effectFor(resource, rule) === "ask");
  if (!asking.length) return { effect: "allow", resources: list };
  return { effect: "ask", rule: asking[0].rule, resources: asking.map((a) => a.resource) };
}

/** An opaque command is not covered by a catch-all allow, only by a specific rule. */
function effectFor(resource: Resource, rule: Rule | undefined): Effect {
  const effect = rule?.effect ?? "ask";
  const catchAll = !rule || rule.resource === "*";
  return effect === "allow" && resource.opaque && catchAll ? "ask" : effect;
}

/** True when the last `*` rule for `action` denies and no later rule can let anything through. */
export function isFullyDenied(rules: Rule[], action: string): boolean {
  let denied = false;
  for (const rule of rules) {
    if (!wildcardMatch(rule.action, action)) continue;
    if (rule.resource === "*") denied = rule.effect === "deny";
    else if (rule.effect !== "deny") denied = false;
  }
  return denied;
}

/**
 * Parses a v2 list (`[{ action, resource, effect }]`), a v1 object
 * (`{ bash: { "git *": "allow" }, edit: "ask" }`) or a bare effect, in order.
 */
export function parseRules(value: unknown, source: string, errors: string[] = []): Rule[] {
  if (value == null) return [];
  if (isEffect(value)) return [{ action: "*", resource: "*", effect: value, source }];
  if (Array.isArray(value)) return parseRuleList(value, source, errors);
  if (typeof value === "object") return parseRuleObject(value as Record<string, unknown>, source, errors);
  errors.push(`${source}: permissions must be a list of rules or an object`);
  return [];
}

function parseRuleList(entries: unknown[], source: string, errors: string[]): Rule[] {
  return entries.flatMap((entry, index) => {
    const { action, resource, effect } = (entry ?? {}) as Record<string, unknown>;
    if (typeof action !== "string" || !isEffect(effect)) {
      errors.push(`${source}: rule ${index} needs a string "action" and an "effect" of allow, ask or deny`);
      return [];
    }
    return [{ action: normalizeAction(action), resource: typeof resource === "string" ? resource : "*", effect, source }];
  });
}

function parseRuleObject(spec: Record<string, unknown>, source: string, errors: string[]): Rule[] {
  return Object.entries(spec).flatMap(([rawAction, patterns]) => {
    const action = normalizeAction(rawAction);
    if (isEffect(patterns)) return [{ action, resource: "*", effect: patterns, source }];
    if (!patterns || typeof patterns !== "object" || Array.isArray(patterns)) {
      errors.push(`${source}: ${rawAction} must be allow, ask, deny or an object of patterns`);
      return [];
    }
    return Object.entries(patterns).flatMap(([resource, effect]) => {
      if (isEffect(effect)) return [{ action, resource, effect, source }];
      errors.push(`${source}: ${rawAction}.${resource} must be allow, ask or deny`);
      return [];
    });
  });
}
