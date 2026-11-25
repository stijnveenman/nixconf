set -euo pipefail

# Remove the current worktree. Ask (gum) before forcing when it has changes.
# Delete the local branch afterwards if its upstream is gone (merged).

pause() {
  printf '\nPress enter to close...'
  read -r _ || true
}
trap 'rc=$?; [ "$rc" -eq 0 ] || pause' EXIT

if ! "$git" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Not in a git repository.\n' >&2
  exit 1
fi

# Main repository: stays valid after the worktree is deleted.
common=$("$git" rev-parse --path-format=absolute --git-common-dir)
branch=$("$git" branch --show-current)

if [ -n "$branch" ]; then
  track=$("$git" fetch --prune --quiet 2>/dev/null; "$git" for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
else
  track=
fi

opts=()
if [ -n "$("$git" status --porcelain --untracked-files=all)" ]; then
  "$git" status --short
  if ! "$gum" confirm "Worktree has uncommitted changes. Remove with --force?"; then
    exit 1
  fi
  opts+=(--force)
fi

# Leave the checkout before it is deleted.
cd "$common/.."
"$wt" -C "$OLDPWD" remove ${opts[@]+"${opts[@]}"}

if [ -n "$branch" ] && [ "$track" = "[gone]" ]; then
  "$git" --git-dir="$common" branch -D "$branch"
fi
