{
  config,
  lib,
  pkgs,
}: let
  sleep = lib.getExe' pkgs.coreutils "sleep";
  tmux = lib.getExe pkgs.tmux;
  worktrunk = lib.getExe config.programs.worktrunk.package;
in
  pkgs.writeShellScript "tmux-worktrunk-picker" ''
    set -eu

    source_pane="''${1:?source pane is required}"
    worktree="$(${tmux} display-message -p -t "$source_pane" '#{pane_current_path}')"
    picker_pane="$(${tmux} split-window -v -b -f -p 20 -t "$source_pane" -c "$worktree" -P -F '#{pane_id}' ${worktrunk} switch)"

    # Wait for Worktrunk to enter its terminal UI before hiding its preview.
    ${sleep} 0.1
    ${tmux} send-keys -t "$picker_pane" M-p
  ''
