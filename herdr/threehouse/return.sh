#!/usr/bin/env bash
#
# threehouse.pool :: return (pane.exited event hook)
#
# A pooled workspace has a single root pane, so it is destroyed when that pane's
# shell exits. herdr does NOT emit workspace.closed for that teardown path, so we
# hook pane.exited and return the leased worktree to the treehouse pool when the
# pane that exited was the workspace's LAST pane (i.e. the workspace is gone or
# being torn down). If other panes remain, the workspace lives on and the lease
# stays held.
#
# The lease-id guard makes return idempotent and ABA-safe: a stale or
# already-returned lease is a no-op, and we never release a later acquisition of
# the same path.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/lib.sh"

[ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ] || exit 0

ws_id="$(
  printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | "$JQ" -r '
    (.workspace_id // .pane.workspace_id // .workspace.workspace_id // empty)
  ' 2>/dev/null || true
)"
[ -n "$ws_id" ] || exit 0

pane_id="$(
  printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | "$JQ" -r '
    (.pane_id // .pane.pane_id // empty)
  ' 2>/dev/null || true
)"

file="$(lease_file "$ws_id")"
[ -f "$file" ] || exit 0 # not one of ours

# Decide whether the workspace is gone / this was its last pane. List the
# workspace's remaining panes: if the workspace no longer exists, or the only
# pane left is the one that just exited, the workspace is being torn down and we
# return the lease. Otherwise other panes remain and we leave it held.
panes_json="$("$HERDR" pane list --workspace "$ws_id" 2>/dev/null || true)"

remaining="$(
  printf '%s' "$panes_json" | "$JQ" -r '
    if (.result.panes | type) == "array"
    then (.result.panes | map(.pane_id) | join("\n"))
    else empty end
  ' 2>/dev/null || true
)"

last_pane=0
if [ -z "$panes_json" ] \
  || printf '%s' "$panes_json" | "$JQ" -e '.error' >/dev/null 2>&1; then
  # workspace_not_found (or unqueryable) -> workspace already gone.
  last_pane=1
else
  # Workspace still queryable: last pane only if nothing remains, or the sole
  # remaining pane is the one that just exited.
  count="$(printf '%s\n' "$remaining" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    last_pane=1
  elif [ "$count" -eq 1 ] && [ -n "$pane_id" ] \
    && [ "$remaining" = "$pane_id" ]; then
    last_pane=1
  fi
fi

[ "$last_pane" -eq 1 ] || exit 0 # other panes remain; keep the lease

path="$("$JQ" -r '.path' "$file")"
lease_id="$("$JQ" -r '.lease_id' "$file")"

if [ -z "$path" ] || [ "$path" = "null" ]; then
  rm -f "$file"
  exit 0
fi

if "$TREEHOUSE" return --force \
  --if-lease-id "$lease_id" \
  --if-lease-holder herdr \
  "$path" >/dev/null 2>&1; then
  log "Returned pooled worktree for $ws_id (last pane exited)."
  rm -f "$file"
else
  # Lease already gone / mismatched, or return refused (e.g. process
  # verification failed). Leave the mapping so the startup reconcile hook can
  # retry; a genuinely returned lease is a no-op next time.
  err "Return for $ws_id did not complete; reconcile will retry on startup."
  exit 0
fi
