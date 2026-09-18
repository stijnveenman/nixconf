export type OutcomeType<T> =
  | { kind: "confirm"; value: T }
  | { kind: "back" }
  | { kind: "close" }
  | { kind: "stale" }
  | { kind: "unsupported" }
  | { kind: "error" };
