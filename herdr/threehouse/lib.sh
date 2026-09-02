# shellcheck shell=bash
# Shared helpers for the threehouse.pool herdr plugin.
#
# Absolute binary paths are substituted by Nix at build time. When running the
# scripts directly for development, these fall back to PATH lookups.
HERDR="@HERDR@"
TREEHOUSE="@TREEHOUSE@"
JQ="@JQ@"
GUM="@GUM@"

# herdr runs plugin commands in the Ghostty/launchd environment, which does NOT
# include the nix profile on PATH. treehouse shells out to `git`, and our own
# scripts use coreutils (tr, sed, basename, grep, ...). Prepend a Nix-provided
# tool PATH so all of those resolve regardless of the inherited environment.
_toolpath='@TOOLPATH@'
_ph='@''TOOLPATH@'
[ "$_toolpath" != "$_ph" ] && export PATH="$_toolpath:${PATH:-}"

# When run before Nix substitution (standalone dev), the values are still the
# literal placeholders; fall back to PATH. Use a split literal so substitution
# never rewrites the comparison target.
_ph='@''HERDR@'
[ "$HERDR" = "$_ph" ] && HERDR="herdr"
_ph='@''TREEHOUSE@'
[ "$TREEHOUSE" = "$_ph" ] && TREEHOUSE="treehouse"
_ph='@''JQ@'
[ "$JQ" = "$_ph" ] && JQ="jq"
_ph='@''GUM@'
[ "$GUM" = "$_ph" ] && GUM="gum"

# Prefer the herdr binary herdr itself injects (portable across install paths).
[ -n "${HERDR_BIN_PATH:-}" ] && HERDR="$HERDR_BIN_PATH"

# Lease mapping store: one file per herdr workspace we created, named by
# workspace id, holding the treehouse path + lease identity needed to return it.
# HERDR_PLUGIN_STATE_DIR is injected for every plugin command; fall back for
# standalone runs.
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/threehouse-herdr}"
LEASE_DIR="$STATE_DIR/leases"

lease_file() {
  # $1 = herdr workspace id (may contain a colon; keep it literal, it is unique)
  printf '%s/%s.json' "$LEASE_DIR" "$1"
}

log() {
  # Human-facing output. For popups this shows in the popup terminal; for hooks
  # it lands in the plugin command log.
  printf '\033[32m🌳 %s\033[0m\n' "$*" >&2
}

err() {
  printf '\033[31m✗ %s\033[0m\n' "$*" >&2
}
