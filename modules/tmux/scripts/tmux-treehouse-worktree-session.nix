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
  grep = lib.getExe' pkgs.gnugrep "grep";
  mktemp = lib.getExe' pkgs.coreutils "mktemp";
  rm = lib.getExe' pkgs.coreutils "rm";
  sesh = lib.getExe pkgs.sesh;
  sleep = lib.getExe' pkgs.coreutils "sleep";
  tmux = lib.getExe pkgs.tmux;

  leaseHolder = pkgs.writeShellScript "tmux-treehouse-lease-holder" ''
    set -euo pipefail

    worktree="''${TMUX_TREEHOUSE_WORKTREE:?}"
    lease_holder="''${TMUX_TREEHOUSE_LEASE_HOLDER:?}"

    cleanup() {
      ${treehouse} return --if-lease-holder "$lease_holder" "$worktree" >/dev/null 2>&1 || true
    }

    trap cleanup EXIT INT TERM

    printf '\n✅ Worktree ready.\n'
    printf '\nThis hidden WT window is the Treehouse lease holder.\n'
    printf 'Worktree: %s\n' "$worktree"
    printf 'Close this WT window (or the tmux session) to return the worktree lease.\n'
    printf 'Treehouse will terminate remaining processes in the worktree during return.\n'

    ${sleep} infinity
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
    worktree=""
    lease_holder=""
    session_created=0
    lease_acquired=0

    error_log="$(${mktemp} "''${TMPDIR:-/tmp}/tmux-treehouse-session.XXXXXX")"
    rendered_log="$error_log.rendered"

    cleanup_temp_files() {
      ${rm} -f "$error_log" "$rendered_log"
    }

    show_error() {
      local summary="$1"

      {
        printf '%s\n\n' "$summary"
        ${cat} "$error_log"
      } >"$rendered_log"

      if [ -n "''${TMUX:-}" ]; then
        ${tmux} display-message -d 10000 "$summary"
        ${tmux} display-popup -E -w 90% -h 70% "${bash} -lc '${cat} \"$rendered_log\"; printf \"\\nPress Enter to close...\"; read -r _'"
      else
        ${cat} "$rendered_log" >&2
      fi
    }

    release_lease_if_needed() {
      if [ "$lease_acquired" -eq 1 ] && [ -n "$lease_holder" ] && [ -n "$worktree" ]; then
        ${treehouse} return --if-lease-holder "$lease_holder" "$worktree" >>"$error_log" 2>&1 || true
      fi
    }

    destroy_session_if_needed() {
      if [ "$session_created" -eq 1 ] && [ -n "$session" ]; then
        ${tmux} kill-session -t "$session" >>"$error_log" 2>&1 || true
      fi
    }

    fail() {
      local summary="$1"
      destroy_session_if_needed
      release_lease_if_needed
      show_error "$summary"
      cleanup_temp_files
      exit 1
    }

    sanitize_branch_for_session_name() {
      local value="$1"
      value="''${value//\//-}"
      value="''${value//:/-}"
      value="''${value//./-}"
      printf '%s' "$value"
    }

    checkout_branch() {
      local target_branch="$1"

      if ${git} show-ref --verify --quiet "refs/heads/$target_branch"; then
        if ${git} switch "$target_branch" >>"$error_log" 2>&1; then
          return 0
        fi

        # Branch may already be checked out in another worktree.
        if ${git} worktree list --porcelain 2>>"$error_log" | ${grep} -Fxq "branch refs/heads/$target_branch"; then
          printf 'git: branch %s already checked out elsewhere; using detached HEAD at refs/heads/%s\n' "$target_branch" "$target_branch" >>"$error_log"
          ${git} switch --detach "refs/heads/$target_branch" >>"$error_log" 2>&1 || fail "git: failed to detach at $target_branch"
          return 0
        fi

        fail "git: failed to switch to $target_branch"
      fi

      if ${git} show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
        ${git} switch --track -c "$target_branch" "origin/$target_branch" >>"$error_log" 2>&1 || fail "git: failed to create tracking branch $target_branch"
        return 0
      fi

      ${git} switch -c "$target_branch" >>"$error_log" 2>&1 || fail "git: failed to create branch $target_branch"
    }

    repo_root="$(${git} rev-parse --show-toplevel 2>>"$error_log")" || fail "git: failed to resolve repository root"
    repo_name="''${repo_root##*/}"
    session="$repo_name@$(sanitize_branch_for_session_name "$branch")"

    if ${tmux} has-session -t "$session" 2>/dev/null; then
      fail "tmux: session already exists ($session)"
    fi

    lease_holder="tmux:''${session}:$$"
    worktree="$(${treehouse} get --lease --lease-holder "$lease_holder" 2>>"$error_log")" || fail "treehouse: failed to acquire leased worktree"
    worktree="''${worktree%%$'\n'*}"
    lease_acquired=1

    if [ -z "$worktree" ] || [ ! -d "$worktree" ]; then
      fail "treehouse: acquired worktree path is invalid ($worktree)"
    fi

    cd "$worktree" 2>>"$error_log" || fail "treehouse: failed to enter worktree ($worktree)"
    checkout_branch "$branch"

    printf -v worktree_arg '%q' "$worktree"
    printf -v lease_holder_arg '%q' "$lease_holder"

    holder_cmd="TMUX_TREEHOUSE_WORKTREE=$worktree_arg TMUX_TREEHOUSE_LEASE_HOLDER=$lease_holder_arg ${leaseHolder}"

    ${tmux} new-session -d -s "$session" -n WT -c "$worktree" "$holder_cmd" >>"$error_log" 2>&1 || fail "tmux: failed to create treehouse session $session"
    session_created=1

    work_window="$(${tmux} new-window -d -P -F '#{window_id}' -t "$session:" -c "$worktree" 2>>"$error_log")" || fail "tmux: failed to create work window"
    ${tmux} select-window -t "$work_window" >>"$error_log" 2>&1 || fail "tmux: failed to select work window"

    # Keep the Treehouse owner hidden from the status bar and prevent automatic
    # rename from exposing it as `sleep`, etc.
    ${tmux} set-option -w -t "$session:WT" automatic-rename off >>"$error_log" 2>&1 || fail "tmux: failed to disable automatic rename for WT"
    ${tmux} set-option -w -t "$session:WT" window-status-format "" >>"$error_log" 2>&1 || fail "tmux: failed to hide WT status entry"
    ${tmux} set-option -w -t "$session:WT" window-status-current-format "" >>"$error_log" 2>&1 || fail "tmux: failed to hide WT current status entry"

    cleanup_temp_files
    ${sesh} connect "$session"
  ''
