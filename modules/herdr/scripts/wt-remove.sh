set -euo pipefail

checkout=$1
# A newly created checkout at the same path must not lose its workspace.
[ ! -e "$checkout" ] || exit 0

# Worktree list no longer contains the deleted checkout; workspace membership
# retains its path. Only close linked workspaces, never a repository's root.
workspaces=$("$herdr" workspace list) || exit 1
ids=$(printf '%s\n' "$workspaces" | "$jq" -r --arg path "$checkout" '
  .result.workspaces[]
  | select(.worktree.is_linked_worktree == true and .worktree.checkout_path == $path)
  | .workspace_id
')
while IFS= read -r id; do
  [ -n "$id" ] || continue
  "$herdr" workspace close "$id" >/dev/null
done <<< "$ids"
