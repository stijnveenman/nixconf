{
  config,
  lib,
  pkgs,
  workmux,
  ...
}: let
  fzfTmux = lib.getExe' pkgs.fzf "fzf-tmux";
  sesh = lib.getExe pkgs.sesh;
  tmux = lib.getExe pkgs.tmux;
  workmuxGoneCleanup = import ./scripts/workmux-gone-cleanup.nix {
    inherit lib pkgs workmux;
  };

  tmuxSessionSwitcher = pkgs.writeShellScript "tmux-session-switcher" ''
    set -euo pipefail

    set +e
    selected="$(
      ${sesh} list -t --icons | ${fzfTmux} -p 80%,70% \
        --no-sort --ansi \
        --border-label ' tmux sessions ' --prompt '🪟  ' \
        --header ' ctrl-a all • ctrl-t tmux • ctrl-x zoxide • ctrl-d tmux kill • ctrl-c new ' \
        --bind 'tab:down,btab:up' \
        --bind 'ctrl-a:change-prompt(⚡  )+reload(${sesh} list --icons)' \
        --bind 'ctrl-t:change-prompt(🪟  )+reload(${sesh} list -t --icons)' \
        --bind 'ctrl-x:change-prompt(📁  )+reload(${sesh} list -z --icons)' \
        --bind 'ctrl-d:execute-silent(${tmux} kill-session -t {2..})+reload(${sesh} list -t --icons)' \
        --preview-window 'right:55%' \
        --preview '${sesh} preview {}'
    )"
    set -e

    if [ -n "$selected" ]; then
      ${sesh} connect "$selected"
      exit $?
    fi
  '';
in {
  home.packages = [pkgs.tmux];
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf.tmux = {
    enableShellIntegration = true;
  };

  programs.sesh = {
    enable = true;
    settings = {};
  };

  xdg.configFile."tmux/plugins/tpm" = {
    source = pkgs.fetchFromGitHub {
      owner = "tmux-plugins";
      repo = "tpm";
      rev = "e261deb1b47614eed3400089ce7197dc68acc4eb";
      hash = "sha256-oRKUZNyJYQXlkeQfbEYiltUEBpvdwn2SoEBWHVUNmrA=";
    };
  };

  xdg.configFile."tmux/tmux.conf".text = ''
    # ---Key bindings
    set -g prefix C-a
    set -g mouse on

    unbind r
    bind r source-file ${config.xdg.configHome}/tmux/tmux.conf

    bind v split-pane -h -c "#{pane_current_path}"
    bind - split-pane -v -c "#{pane_current_path}"
    bind-key -n C-_ display-popup -w 80% -h 50% -d "#{session_path}"

    bind n next-window
    bind p previous-window
    bind c new-window
    bind x kill-pane
    unbind l
    bind l run-shell "workmux last-done"
    bind b run-shell "workmux sidebar"
    bind [ run-shell "workmux sidebar prev"
    bind ] run-shell "workmux sidebar next"

    # Run one guarded cleanup loop per tmux server. It sweeps all projects
    # tracked by workmux every five minutes; output is in XDG_STATE_HOME.
    run-shell -b "${workmuxGoneCleanup}"

    bind-key -n C-g display-popup -E -w 80% -h 80% lazygit

    # Replace tmux's default worktree picker binding.
    unbind w
    bind f run-shell "${tmuxSessionSwitcher}"

    set-option -g pane-border-status top
    set-option -g pane-border-lines heavy
    set-option -g pane-border-indicators off
    set-option -g pane-border-format ""

    # Enable OSC 8 hyperlink passthrough for Ghostty
    set -g allow-passthrough on
    set -as terminal-features ",xterm-ghostty:hyperlinks"

    # --- Sensible defaults
    set -s escape-time 0
    set -g history-limit 50000
    set -g display-time 4000
    set -g status-interval 5
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",*:RGB"
    set -g status-keys emacs
    set -g focus-events on
    set -g extended-keys on
    set -g extended-keys-format csi-u
    set -g detach-on-destroy off
    setw -g aggressive-resize on
    setw -g automatic-rename on

    set -g @plugin 'tmux-plugins/tpm'

    # --- plugins
    set -g @plugin 'egel/tmux-gruvbox'
    set -g @tmux-gruvbox 'dark'
    set-option -g status-position top
    set -g @tmux-gruvbox-right-status-z ' '

    set -g @plugin 'christoomey/vim-tmux-navigator'
    set -g @vim_navigator_mapping_left "C-h"
    set -g @vim_navigator_mapping_right "C-l"
    set -g @vim_navigator_mapping_up "C-k"
    set -g @vim_navigator_mapping_down "C-j"
    set -g @vim_navigator_mapping_prev ""

    run '${config.xdg.configHome}/tmux/plugins/tpm/tpm'
  '';
}
