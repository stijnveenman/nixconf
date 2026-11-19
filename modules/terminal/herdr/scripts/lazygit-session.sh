set -euo pipefail

# Outside a git checkout there is no worktree to key a session on.
if ! root=$("$git" rev-parse --show-toplevel 2>/dev/null); then
  exec "$lazygit"
fi
cd "$root"

# One nested session per worktree: a readable prefix plus a hash of the path.
base=$(basename "$root")
base=${base//[^a-zA-Z0-9_-]/-}
hash=$(printf '%s' "$root" | "$cksum")
hash=${hash%% *}
session="lg-${base:0:40}-$hash"

export HERDR_CONFIG_PATH=$nested_config

running=$("$herdr" session list --json | "$jq" -r --arg name "$session" \
  '.sessions[] | select(.name == $name) | .running')
if [ "$running" != true ]; then
  # Start fresh so the new server seeds one workspace at this worktree.
  "$herdr" session delete "$session" >/dev/null 2>&1 || :

  # The attach below spawns the server; start lazygit once its first pane
  # exists. Quitting lazygit stops the session, which closes the popup.
  (
    deadline=$((SECONDS + 15))
    while [ "$SECONDS" -lt "$deadline" ]; do
      pane=$("$herdr" --session "$session" pane list 2>/dev/null |
        "$jq" -r '.result.panes[0].pane_id // empty' 2>/dev/null) || pane=
      if [ -n "$pane" ]; then
        "$herdr" --session "$session" pane run "$pane" \
          "$lazygit; $herdr session stop $session" >/dev/null
        exit 0
      fi
      sleep 0.1
    done
  ) &
fi

exec "$herdr" --session "$session"
