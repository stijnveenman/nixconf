set -euo pipefail

usage() {
  printf 'usage: wt remove-gone [--force] [--foreground]\n\n'
  printf 'Remove worktrees whose upstream branch was merged and deleted (gone).\n\n'
  printf '  -f, --force   remove dirty worktrees and delete unmerged branches\n'
  printf '  --foreground  block until each removal completes\n'
}

opts=()
for arg in "$@"; do
  case $arg in
    -f | --force) opts+=(--force --force-delete) ;;
    --foreground) opts+=(--foreground) ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# Prune deleted remote branches so their local upstreams report as gone.
"$git" fetch --all --prune --quiet

# Linked worktrees on a branch, with the current worktree last so removing it
# happens after every other removal.
branches=$("$wt" list --format=json | "$jq" -r '
  [.items[] | select(.worktree != null and .worktree.main == false and .branch != null)]
  | sort_by(.worktree.current)
  | .[].branch
')

gone=()
while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  track=$("$git" for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
  [ "$track" = "[gone]" ] && gone+=("$branch")
done <<<"$branches"

if [ "${#gone[@]}" -eq 0 ]; then
  printf 'No worktrees with a gone upstream.\n'
  exit 0
fi

status=0
for branch in "${gone[@]}"; do
  printf 'Removing %s (upstream gone)\n' "$branch"
  "$wt" remove "${opts[@]}" "$branch" || status=1
done
exit "$status"
