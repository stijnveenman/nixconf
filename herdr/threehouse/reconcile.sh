#!/usr/bin/env bash
#
# threehouse.pool :: reconcile (startup hook)
#
# Runs after herdr restores a session and on live handoff. Safety net for the
# workspace.closed hook: returns any leased worktree whose owning herdr
# workspace no longer exists (e.g. herdr was force-killed before the close hook
# could fire), and drops mapping files for leases treehouse no longer knows.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/lib.sh"

[ -d "$LEASE_DIR" ] || exit 0

# Current live workspace ids.
live="$(
  "$HERDR" workspace list 2>/dev/null \
    | "$JQ" -r '.result.workspaces[].workspace_id' 2>/dev/null || true
)"

is_live() {
  printf '%s\n' "$live" | grep -Fxq "$1"
}

shopt -s nullglob
for file in "$LEASE_DIR"/*.json; do
  ws_id="$("$JQ" -r '.workspace_id' "$file" 2>/dev/null || true)"
  path="$("$JQ" -r '.path' "$file" 2>/dev/null || true)"
  lease_id="$("$JQ" -r '.lease_id' "$file" 2>/dev/null || true)"

  [ -n "$ws_id" ] || {
    rm -f "$file"
    continue
  }

  if is_live "$ws_id"; then
    continue # workspace still open; leave the lease held
  fi

  # Orphaned: workspace gone but lease mapping remains. Return it.
  if [ -n "$path" ] && [ "$path" != "null" ]; then
    if "$TREEHOUSE" return --force \
      --if-lease-id "$lease_id" \
      --if-lease-holder herdr \
      "$path" >/dev/null 2>&1; then
      log "Reconciled: returned orphaned worktree for $ws_id."
    fi
  fi
  rm -f "$file"
done
