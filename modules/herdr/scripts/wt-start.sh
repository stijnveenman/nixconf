set -euo pipefail

usage() {
  printf '%s\n' 'Usage: wt start <branch> [--base <base>] [--prompt|-p <prompt> | --prompt-file <file>] [--focus]'
}

fail() {
  printf 'wt start: %s\n' "$*" >&2
  exit 1
}

branch=
base=
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

"$herdr" agent start "$name" --kind pi --pane "$pane" --timeout 60000 >/dev/null
if [ -n "$prompt" ]; then
  "$herdr" agent prompt "$name" "$prompt" >/dev/null
fi
if "$focus"; then
  "$herdr" agent focus "$name" >/dev/null
fi
printf 'Started %s in %s (workspace %s, pane %s)\n' "$name" "$checkout" "$workspace" "$pane"
