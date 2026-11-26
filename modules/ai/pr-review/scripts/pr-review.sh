set -euo pipefail

usage() {
  printf '%s\n' 'Usage: pr-review <owner/repo> <number>'
}

notify() {
  "$herdr" notification show "$1" --body "$2" --sound "${3:-done}" >/dev/null 2>&1 || :
}

fail() {
  printf 'pr-review: %s\n' "$*" >&2
  # gh-dash clears the screen when the command returns, so also raise a toast.
  notify "PR review failed" "$*" request
  exit 1
}

[ "$#" -eq 2 ] || { usage >&2; exit 1; }
repo=$1
pr=$2
[[ $repo =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || fail "invalid repository: $repo"
[[ $pr =~ ^[0-9]+$ ]] || fail "invalid pull request number: $pr"
label="PR Review #$pr"

# Prints owner/repo for every remote of the checkout at $1, lowercased.
remote_repos() {
  local remote url rest
  for remote in $("$git" -C "$1" remote 2>/dev/null); do
    url=$("$git" -C "$1" remote get-url "$remote" 2>/dev/null) || continue
    url=${url%/}
    url=${url%.git}
    rest=${url%/*}
    printf '%s/%s\n' "${rest##*[:/]}" "${url##*/}"
  done | tr '[:upper:]' '[:lower:]'
}

# The main worktree of a checkout whose remotes include $repo.
main_worktree() {
  local repos
  "$git" -C "$1" rev-parse --git-dir >/dev/null 2>&1 || return 1
  repos=$(remote_repos "$1")
  grep -qxF "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')" <<<"$repos" || return 1
  "$git" -C "$1" worktree list --porcelain | sed -n '1s/^worktree //p'
}

# Prefer the directory gh-dash runs in, then any checkout open in Herdr.
repo_root=
candidates=("$PWD")
while IFS= read -r root; do
  [ -n "$root" ] && candidates+=("$root")
done < <("$herdr" workspace list | "$jq" -r '.result.workspaces[].worktree.repo_root // empty' | sort -u)
for candidate in "${candidates[@]}"; do
  if repo_root=$(main_worktree "$candidate") && [ -n "$repo_root" ]; then
    break
  fi
  repo_root=
done
[ -n "$repo_root" ] || fail "no local checkout of $repo; open it in Herdr first"

# The workspace of the main worktree, opened in the background if needed.
worktrees=$("$herdr" worktree list --cwd "$repo_root")
workspace=$(printf '%s\n' "$worktrees" | "$jq" -r \
  '.result.worktrees[] | select(.is_linked_worktree | not) | .open_workspace_id // empty' | head -n1)
if [ -z "$workspace" ]; then
  opened=$("$herdr" worktree open --cwd "$repo_root" --path "$repo_root" --no-focus)
  workspace=$(printf '%s\n' "$opened" | "$jq" -er '.result.workspace.workspace_id')
fi

# One review tab per PR: switch to it when it already exists.
existing=$("$herdr" tab list --workspace "$workspace" | "$jq" -r --arg label "$label" \
  '.result.tabs[] | select(.label == $label) | .tab_id' | head -n1)
if [ -n "$existing" ]; then
  "$herdr" tab focus "$existing" >/dev/null
  exit 0
fi

created=$("$herdr" tab create --workspace "$workspace" --cwd "$repo_root" --label "$label" --no-focus)
tuicr_pane=$(printf '%s\n' "$created" | "$jq" -er '.result.root_pane.pane_id')
split=$("$herdr" pane split "$tuicr_pane" --direction right --cwd "$repo_root" --no-focus)
pi_pane=$(printf '%s\n' "$split" | "$jq" -er '.result.pane.pane_id')

name="pr-$pr-${repo##*/}"
name=${name,,}
name=${name//[^a-z0-9_-]/-}
name=${name:0:32}

# Everything below waits on tuicr and Pi; detach so gh-dash returns at once.
log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/pr-review
mkdir -p "$log_dir"
log=$log_dir/$name.log

background() {
  # Closing the gh-dash popup hangs up its process group, which includes this.
  trap '' HUP
  bg_fail() {
    printf 'pr-review: %s\n' "$*" >&2
    notify "PR #$pr review failed" "$* (log: $log)" request
    exit 1
  }

  # tuicr creates the PR session when the review opens; comments can only be
  # added to an existing session, and the open TUI shows them as they land.
  "$herdr" pane run "$tuicr_pane" "tuicr pr $repo#$pr" >/dev/null
  session=
  deadline=$((SECONDS + 300))
  while [ -z "$session" ]; do
    [ "$SECONDS" -lt "$deadline" ] || bg_fail "tuicr did not open $repo#$pr"
    sleep 1
    session=$(tuicr review list --repo "$repo" 2>/dev/null | "$jq" -r --arg anchor "pr/$pr" \
      'map(select(.kind == "pr" and .anchor == $anchor)) | first | .slug // empty' 2>/dev/null) || session=
  done

  # A new pane is busy while shell init runs (e.g. direnv); retry until ready.
  deadline=$((SECONDS + 300))
  while ! start_err=$("$herdr" agent start "$name" --kind pi --pane "$pi_pane" --timeout 60000 \
    -- --model "$model" --name "$label" 2>&1 >/dev/null); do
    code=$(printf '%s\n' "$start_err" | "$jq" -r '.error.code? // empty' 2>/dev/null) || code=
    if [ "$code" != agent_pane_busy ] || [ "$SECONDS" -ge "$deadline" ]; then
      printf '%s\n' "$start_err" >&2
      bg_fail "could not start pi in pane $pi_pane"
    fi
    sleep 0.5
  done
  # The Herdr Agents sidebar shows "PR #N" instead of "pi" for this pane until
  # pi exits (dimmed by modules/terminal/herdr/default.nix).
  "$herdr" pane report-metadata "$pi_pane" --source pr-review --agent pi \
    --display-agent "PR #$pr" >/dev/null || :

  # Herdr can report Pi ready while its project-trust selector is still open.
  # Pi sets this title once its interactive UI and extensions are initialized.
  deadline=$((SECONDS + 300))
  while :; do
    agent_json=$("$herdr" agent get "$name") || bg_fail "cannot inspect $name"
    title=$(printf '%s\n' "$agent_json" | "$jq" -r '.result.agent.terminal_title_stripped // ""')
    status=$(printf '%s\n' "$agent_json" | "$jq" -r '.result.agent.agent_status // ""')
    if [[ $title == 'π - '* ]]; then
      [ "$status" != blocked ] || bg_fail "$name is blocked before the review started"
      break
    fi
    [ "$SECONDS" -lt "$deadline" ] || bg_fail "timed out waiting for pi in $label"
    sleep 0.25
  done

  "$herdr" agent prompt "$name" "/skill:pr-review $repo#$pr tuicr session: $session" \
    --wait --until working --timeout 15000 >/dev/null ||
    bg_fail "could not confirm the review prompt reached $name"

  status=$("$herdr" agent wait "$name" | "$jq" -r '.result.agent.agent_status // empty') ||
    bg_fail "lost track of $name before the review finished"
  if [ "$status" = blocked ]; then
    notify "PR #$pr review needs input" "$repo · $label" request
  else
    notify "PR #$pr review ready" "$repo · $label"
  fi
}

background </dev/null >"$log" 2>&1 &
disown
printf 'Started %s for %s#%s (log: %s)\n' "$label" "$repo" "$pr" "$log"
