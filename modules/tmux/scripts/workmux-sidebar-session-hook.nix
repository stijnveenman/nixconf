{
  lib,
  pkgs,
  workmux,
}: let
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
  tmux = lib.getExe pkgs.tmux;
in
  # tmux session-created hook: enable the workmux sidebar for this session only
  # (never globally), skipping tmux-tpad and scratch sessions.
  pkgs.writeShellScript "workmux-sidebar-session-hook" ''
    session="''${1:-}"
    [ -n "$session" ] || exit 0

    case "$session" in
      tpad_*|scratch) exit 0 ;;
    esac

    pane="$(${tmux} display-message -p -t "$session:" '#{pane_id}' 2>/dev/null)" || exit 0
    TMUX_PANE="$pane" ${workmuxExe} sidebar --session on >/dev/null 2>&1 || true
  ''
