#!/usr/bin/env bash
#
# threehouse.pool :: new
#
# Popup entrypoint. Prompts for a workspace name and (optionally) a base branch
# with gum, leases a worktree from the treehouse pool for the repo the popup was
# launched from, opens it as a first-class herdr workspace, and records the
# lease so it can be returned when the workspace closes.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/lib.sh"

# Fail in a way the user can actually read: print the error, then hold the popup
# open until a key is pressed (herdr closes the popup the moment this process
# exits). A generous timeout prevents a wedged popup if nothing is watching.
die() {
  local line
  for line in "$@"; do
    err "$line"
  done
  printf '\n\033[2mPress any key to close…\033[0m' >&2
  read -r -n 1 -t 120 _ </dev/tty 2>/dev/null || true
  printf '\n' >&2
  exit 1
}

mkdir -p "$LEASE_DIR"

# --- Resolve the source repo -------------------------------------------------
# The popup process starts with the plugin dir as cwd, so we must find the repo
# the user launched from. herdr injects HERDR_PLUGIN_CONTEXT_JSON with the
# focused pane / workspace; prefer the focused pane's foreground cwd, then the
# workspace cwd.
src_cwd=""
if [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
  src_cwd="$(
    printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | "$JQ" -r '
      (.pane.foreground_cwd // .pane.cwd // .workspace.cwd // empty)
    ' 2>/dev/null || true
  )"
fi

# Fall back to querying the focused workspace's root pane over the API.
if [ -z "$src_cwd" ]; then
  src_cwd="$(
    "$HERDR" pane current 2>/dev/null \
      | "$JQ" -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null || true
  )"
fi

if [ -z "$src_cwd" ] || [ ! -d "$src_cwd" ]; then
  die "Could not determine the source repository directory." \
    "Launch the popup from a pane inside a git repository."
fi

cd "$src_cwd"

# Confirm we are in a git repo (treehouse needs one).
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  die "Not inside a git repository: $src_cwd"
fi
repo_name="$(basename "$(git rev-parse --show-toplevel)")"

# --- Form --------------------------------------------------------------------
# Two sequential gum inputs. Field 1 (name) is required. Field 2 (base) is
# pre-empty: leave it blank and treehouse infers the base branch (origin/HEAD,
# etc). Type a branch only to override.
name="$(
  "$GUM" input \
    --header "New pooled workspace ($repo_name)" \
    --placeholder "workspace name" \
    --prompt "name › "
)" || exit 0 # esc / ctrl+c cancels cleanly

name="$(printf '%s' "$name" | tr -d '[:cntrl:]' | sed 's/^ *//;s/ *$//')"
if [ -z "$name" ]; then
  die "A workspace name is required."
fi

base="$(
  "$GUM" input \
    --header "Base branch (blank = repo default)" \
    --placeholder "leave blank for default" \
    --prompt "base › "
)" || exit 0

base="$(printf '%s' "$base" | tr -d '[:cntrl:]' | sed 's/^ *//;s/ *$//')"

# --- Lease a worktree from the pool -----------------------------------------
log "Leasing a worktree from the pool…"
base_args=()
[ -n "$base" ] && base_args=(--base "$base")

lease_json="$(
  "$TREEHOUSE" get --lease --lease-holder herdr --no-fetch --json "${base_args[@]}"
)" || die "treehouse failed to lease a worktree." \
  "Run 'treehouse status' in $repo_name to inspect the pool."

path="$(printf '%s' "$lease_json" | "$JQ" -r '.path')"
lease_id="$(printf '%s' "$lease_json" | "$JQ" -r '.lease_id')"
resolved_base="$(printf '%s' "$lease_json" | "$JQ" -r '.base_branch // empty')"

if [ -z "$path" ] || [ "$path" = "null" ] || [ ! -d "$path" ]; then
  die "treehouse returned an invalid worktree path."
fi

# --- Open as a herdr workspace ----------------------------------------------
# herdr rejects adopting an external linked-worktree via `worktree open`, so we
# create a plain workspace rooted at the leased checkout. It is a first-class
# sidebar workspace.
create_json="$(
  "$HERDR" workspace create --cwd "$path" --label "$name" --focus
)" || {
  "$TREEHOUSE" return --force --if-lease-id "$lease_id" --if-lease-holder herdr "$path" >/dev/null 2>&1 || true
  die "herdr failed to create the workspace; the lease was returned."
}

ws_id="$(printf '%s' "$create_json" | "$JQ" -r '.result.workspace.workspace_id')"
if [ -z "$ws_id" ] || [ "$ws_id" = "null" ]; then
  "$TREEHOUSE" return --force --if-lease-id "$lease_id" --if-lease-holder herdr "$path" >/dev/null 2>&1 || true
  die "Could not read the new workspace id; the lease was returned."
fi

# --- Record the mapping for return-on-close ---------------------------------
"$JQ" -n \
  --arg ws "$ws_id" \
  --arg path "$path" \
  --arg lease_id "$lease_id" \
  --arg name "$name" \
  --arg repo "$repo_name" \
  --arg base "$resolved_base" \
  '{workspace_id:$ws, path:$path, lease_id:$lease_id, name:$name, repo:$repo, base:$base}' \
  >"$(lease_file "$ws_id")"

# Decorate the sidebar row with repo + base so pooled workspaces are legible.
"$HERDR" workspace report-metadata "$ws_id" \
  --source threehouse \
  --token repo="$repo_name" \
  ${resolved_base:+--token base="$resolved_base"} \
  >/dev/null 2>&1 || true

log "Opened '$name' in a pooled worktree ($repo_name)."
