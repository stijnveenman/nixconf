set -euo pipefail

usage() {
  printf '%s\n' 'Usage: wt start <branch> [--base <base>] [--model <model>] [--prompt|-p <prompt> | --prompt-file <file>] [--focus]'
}

fail() {
  printf 'wt start: %s\n' "$*" >&2
  exit 1
}

branch=
base=
model=
prompt=
prompt_file=
prompt_source=
focus=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--base requires a value'
      base=$2
      shift 2
      ;;
    --model)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--model requires a value'
      model=$2
      shift 2
      ;;
    --prompt|-p)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 requires a prompt"
      [ "$prompt_source" != file ] || fail '--prompt and --prompt-file cannot be combined'
      prompt_source=text
      prompt=$2
      shift 2
      ;;
    --prompt-file)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--prompt-file requires a path'
      [ "$prompt_source" != text ] || fail '--prompt and --prompt-file cannot be combined'
      prompt_source=file
      prompt_file=$2
      shift 2
      ;;
    --focus)
      focus=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*) fail "unknown option: $1" ;;
    *)
      [ -z "$branch" ] || fail "unexpected argument: $1"
      branch=$1
      shift
      ;;
  esac
done
[ -n "$branch" ] || { usage >&2; exit 1; }
if [ "$prompt_source" = file ]; then
  [ -f "$prompt_file" ] && [ -r "$prompt_file" ] || fail "cannot read prompt file: $prompt_file"
  # read preserves trailing newlines; EOF returns nonzero for a text file.
  IFS= read -r -d '' prompt < "$prompt_file" || :
  [ -n "$prompt" ] || fail "prompt file is empty: $prompt_file"
fi
"$git" check-ref-format --branch "$branch" >/dev/null

# Resolve repository identity from cwd, never from whichever workspace is focused.
source_json=$("$herdr" worktree list --cwd "$PWD")
repo_root=$(printf '%s\n' "$source_json" | "$jq" -er '.result.source.repo_root | select(type == "string" and length > 0)')

args=(switch --no-cd --format=json)
if ! "$git" show-ref --verify --quiet "refs/heads/$branch"; then
  args+=(--create)
fi
# Worktrunk resolves and validates bases, including shortcuts such as pr:123.
[ -z "$base" ] || args+=(--base "$base")
result=$("$wt" "${args[@]}" "$branch")
checkout=$(printf '%s\n' "$result" | "$jq" -er '.path | select(type == "string" and length > 0)')

# Opening via the primary checkout nests the workspace under the correct repo,
# including when this command was invoked inside another linked worktree.
opened=$("$herdr" worktree open --cwd "$repo_root" --path "$checkout" --label "$branch" --no-focus)
workspace=$(printf '%s\n' "$opened" | "$jq" -er '.result.workspace.workspace_id | select(type == "string" and length > 0)')
root_pane=$(printf '%s\n' "$opened" | "$jq" -er '.result.root_pane.pane_id | select(type == "string" and length > 0)')

# Always use a new pane: an existing workspace may have a busy root terminal.
split=$("$herdr" pane split "$root_pane" --direction right --cwd "$checkout" --no-focus)
pane=$(printf '%s\n' "$split" | "$jq" -er '.result.pane.pane_id | select(type == "string" and length > 0)')
name="pi-${pane//[^a-zA-Z0-9]/-}"
name=${name,,}
name=${name:0:32}

agent_args=()
[ -z "$model" ] || agent_args+=(-- --model "$model")
# A new pane is busy while shell init runs (e.g. direnv evaluating a flake for
# a fresh checkout). Herdr rejects the start before sending input, so retry.
deadline=$((SECONDS + 300))
announced=false
while ! start_err=$("$herdr" agent start "$name" --kind pi --pane "$pane" --timeout 60000 "${agent_args[@]}" 2>&1 >/dev/null); do
  code=$(printf '%s\n' "$start_err" | "$jq" -r '.error.code? // empty' 2>/dev/null) || code=
  if [ "$code" != agent_pane_busy ] || [ "$SECONDS" -ge "$deadline" ]; then
    printf '%s\n' "$start_err" >&2
    fail "could not start pi in pane $pane"
  fi
  if ! "$announced"; then
    printf 'Waiting for shell initialization in pane %s (e.g. direnv).\n' "$pane" >&2
    announced=true
  fi
  sleep 0.5
done
if "$focus"; then
  "$herdr" agent focus "$name" >/dev/null
fi
if [ -n "$prompt" ]; then
  # Herdr can report Pi ready while its project-trust selector is still open.
  # Pi sets this title after its interactive UI and startup extensions initialize.
  deadline=$((SECONDS + 300))
  announced=false
  while :; do
    agent_json=$("$herdr" agent get "$name") || fail "cannot inspect $name; prompt was not sent"
    title=$(printf '%s\n' "$agent_json" | "$jq" -r '.result.agent.terminal_title_stripped // ""')
    status=$(printf '%s\n' "$agent_json" | "$jq" -r '.result.agent.agent_status // ""')
    if [[ $title == 'π - '* ]]; then
      [ "$status" != blocked ] || fail "$name is blocked; prompt was not sent"
      break
    fi
    if ! "$announced"; then
      printf 'Waiting for Pi startup in %s; resolve any project-trust dialog there.\n' "$name" >&2
      announced=true
    fi
    [ "$SECONDS" -lt "$deadline" ] || fail "timed out waiting for $name; prompt was not sent"
    sleep 0.25
  done
  # Confirm the turn starts, but do not wait for the task to finish or retry a
  # stalled submission: Herdr cannot prove that a timed-out prompt was lost.
  if ! "$herdr" agent prompt "$name" "$prompt" --wait --until working --timeout 15000 >/dev/null; then
    fail "could not confirm prompt delivery to $name; it may already have been sent, so inspect the pane before retrying"
  fi
fi
printf 'Started %s in %s (workspace %s, pane %s)\n' "$name" "$checkout" "$workspace" "$pane"
