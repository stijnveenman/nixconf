{
  config,
  lib,
  pkgs,
}: let
  treehouse = lib.getExe (
    if config ? treehouse && config.treehouse ? package
    then config.treehouse.package
    else pkgs.treehouse
  );

  bash = lib.getExe pkgs.bash;
  cat = lib.getExe' pkgs.coreutils "cat";
  git = lib.getExe pkgs.git;
  mktemp = lib.getExe' pkgs.coreutils "mktemp";
  rm = lib.getExe' pkgs.coreutils "rm";
  sesh = lib.getExe pkgs.sesh;
  tmux = lib.getExe pkgs.tmux;

  launchShell = pkgs.writeShellScript "tmux-treehouse-launch-shell" ''
    set -euo pipefail

    branch="''${TMUX_TREEHOUSE_BRANCH:?}"
    safe_branch="''${TMUX_TREEHOUSE_SAFE_BRANCH:?}"
    session="''${TMUX_TREEHOUSE_SESSION:?}"

    fail() {
      printf '\n❌ %s\n' "$1" >&2
      printf '\nTreehouse will return this worktree when this launcher exits.\n' >&2
      printf 'Press Enter to close launcher and return worktree...' >&2
      read -r _ || true
      exit 1
    }

    printf '\n🌳 Treehouse acquired worktree:\n  %s\n' "$PWD"
    printf '🌿 Preparing branch:\n  %s\n\n' "$branch"

    if ${git} show-ref --verify --quiet "refs/heads/$branch"; then
      ${git} switch "$branch" || fail "git: failed to switch to $branch"
    elif ${git} show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      ${git} switch --track -c "$branch" "origin/$branch" || fail "git: failed to create tracking branch $branch"
    else
      ${git} switch -c "$branch" || fail "git: failed to create branch $branch"
    fi

    printf '\n🪟 Opening work window for %s...\n' "$session"
    work_window="$(${tmux} new-window -d -P -F '#{window_id}' -t "$session:" -c "$PWD")" || fail "tmux: failed to create work window"

    ${tmux} select-window -t "$work_window" || fail "tmux: failed to select work window"

    printf '\n✅ Worktree ready.\n'
    printf '\nThis hidden WT window is the Treehouse lease holder.\n'
    printf 'Press any key in this WT window to return the worktree lease.\n'
    printf 'Treehouse will terminate remaining processes in the worktree during return.\n'

    read -rsn 1 _ || true
    exit 0
  '';
in
  pkgs.writeShellScript "tmux-treehouse-worktree-session" ''
    set -euo pipefail

    branch="''${1:-}"
    if [ -z "$branch" ]; then
      ${tmux} display-message -d 10000 "treehouse: branch name is required"
      exit 1
    fi

    session=""
    session_created=0
    error_log="$(${mktemp} "''${TMPDIR:-/tmp}/tmux-treehouse-session.XXXXXX")"

    show_error() {
      local summary="$1"

      {
        printf '%s\n\n' "$summary"
        ${cat} "$error_log"
      } >"$error_log.rendered"

      if [ -n "''${TMUX:-}" ]; then
        ${tmux} display-message -d 10000 "$summary"
        ${tmux} display-popup -E -w 90% -h 70% "${bash} -lc '${cat} \"$error_log.rendered\"; printf \"\\nPress Enter to close...\"; read -r _'"
      else
        ${cat} "$error_log.rendered" >&2
      fi
    }

    cleanup_on_failure() {
      if [ "$session_created" -eq 1 ] && [ -n "$session" ]; then
        ${tmux} kill-session -t "$session" >>"$error_log" 2>&1 || true
      fi
    }

    fail() {
      local summary="$1"
      cleanup_on_failure
      show_error "$summary"
      exit 1
    }

    repo_root="$(${git} rev-parse --show-toplevel 2>>"$error_log")" || fail "git: failed to resolve repository root"
    repo_name="''${repo_root##*/}"

    # tmux session names cannot contain '.' or ':'; keep them filesystem-safe too.
    safe_branch="''${branch//\//-}"
    safe_branch="''${safe_branch//:/-}"
    safe_branch="''${safe_branch//./-}"
    session="$repo_name@$safe_branch"

    if ${tmux} has-session -t "$session" 2>/dev/null; then
      fail "tmux: session already exists ($session)"
    fi

    printf -v branch_arg '%q' "$branch"
    printf -v safe_branch_arg '%q' "$safe_branch"
    printf -v session_arg '%q' "$session"

    launch_cmd="TMUX_TREEHOUSE_BRANCH=$branch_arg TMUX_TREEHOUSE_SAFE_BRANCH=$safe_branch_arg TMUX_TREEHOUSE_SESSION=$session_arg SHELL=${launchShell} ${treehouse} get"

    ${tmux} new-session -d -s "$session" -n WT -c "$repo_root" "$launch_cmd" >>"$error_log" 2>&1 || fail "tmux: failed to create treehouse launcher session $session"
    session_created=1

    # Keep the Treehouse owner hidden from the status bar and prevent automatic
    # rename from exposing it as `treehouse`, `bash`, etc.
    ${tmux} set-option -w -t "$session:WT" automatic-rename off >>"$error_log" 2>&1 || fail "tmux: failed to disable automatic rename for WT"
    ${tmux} set-option -w -t "$session:WT" window-status-format "" >>"$error_log" 2>&1 || fail "tmux: failed to hide WT status entry"
    ${tmux} set-option -w -t "$session:WT" window-status-current-format "" >>"$error_log" 2>&1 || fail "tmux: failed to hide WT current status entry"

    ${rm} -f "$error_log" "$error_log.rendered"

    ${sesh} connect "$session"
  ''
