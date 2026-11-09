set -euo pipefail

checkout=$1
# Worktrunk starts post-remove hooks before background removal finishes. Wait
# for the checkout to disappear, but never close a workspace if it remains.
deadline=$((SECONDS + ${WT_HERDR_REMOVE_TIMEOUT:-120}))
while [ -e "$checkout" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    printf 'wt-remove-herdr: checkout still exists, leaving workspace open: %s\n' "$checkout" >&2
    exit 1
  fi
  sleep 0.25
done

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
  # Do not close a workspace if the checkout was recreated during lookup.
  [ ! -e "$checkout" ] || exit 0
  "$herdr" workspace close "$id" >/dev/null
done <<< "$ids"
