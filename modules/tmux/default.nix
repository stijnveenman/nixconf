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
  workmuxSidebarOpenPr = import ./scripts/workmux-sidebar-open-pr.nix {
    inherit lib pkgs workmux;
  };

  workmuxSidebarSessionHook = import ./scripts/workmux-sidebar-session-hook.nix {
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

  # Expose the writeShellScript without putting its single-file output in
  # home.packages (which only accepts package directories).
  home.file.".local/bin/workmux-sidebar-open-pr".source = workmuxSidebarOpenPr;
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf.tmux = {
    enableShellIntegration = true;
  };

  programs.sesh = {
    enable = true;
    settings.blacklist = ["^scratch$" "^tpad_"];
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

    bind n next-window
    bind p previous-window
    bind c new-window
    bind x kill-pane
    unbind l
    bind l run-shell "workmux last-done"
    bind b run-shell "workmux sidebar --session"
    bind [ run-shell "workmux sidebar prev"
    bind ] run-shell "workmux sidebar next"

    # Enable the workmux sidebar per session (not globally); tpad sessions skipped.
    set-hook -g session-created 'run-shell -b "${workmuxSidebarSessionHook} #{hook_session_name}"'

    # Open the highlighted sidebar row's pull request without blocking tmux.
    # Forward O unchanged when a non-sidebar pane is focused.
    bind-key -n O if-shell -F '#{==:#{@workmux_role},sidebar}' 'run-shell -b "${config.home.homeDirectory}/.local/bin/workmux-sidebar-open-pr || true"' 'send-keys O'

    # Replace tmux's default worktree picker binding.
    unbind w
    bind F run-shell "${tmuxSessionSwitcher}"

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
    set -g @plugin 'catppuccin/tmux'
    set -g @catppuccin_flavor 'mocha'
    set -g @catppuccin_window_status_style "rounded"
    set -g @catppuccin_window_text ' #W'
    set -g @catppuccin_window_current_text ' #W'
    set-option -g status-position top

    set -g @plugin 'christoomey/vim-tmux-navigator'
    set -g @vim_navigator_mapping_left "C-h"
    set -g @vim_navigator_mapping_right "C-l"
    set -g @vim_navigator_mapping_up "C-k"
    set -g @vim_navigator_mapping_down "C-j"
    set -g @vim_navigator_mapping_prev ""

    # Floating windows via tmux-tpad (root table: no prefix needed).
    set -g @plugin 'Subbeh/tmux-tpad'

    set -g @tpad-scratchpad-cmd    "zsh"
    set -g @tpad-scratchpad-bind   "C-_"
    set -g @tpad-scratchpad-table  "root"
    set -g @tpad-scratchpad-width  "80%"
    set -g @tpad-scratchpad-height "50%"
    set -g @tpad-scratchpad-dir    "#{pane_current_path}"

    set -g @tpad-git-bind          "C-g"
    set -g @tpad-git-table         "root"
    set -g @tpad-git-cmd           "lazygit"
    set -g @tpad-git-per-dir       "true"
    set -g @tpad-git-width         "80%"
    set -g @tpad-git-height        "80%"

    set -g @tpad-dashboard-bind    "f"
    set -g @tpad-dashboard-cmd     "workmux dashboard --tab worktrees --preview-size 10"
    set -g @tpad-dashboard-dir     "#{pane_current_path}"
    set -g @tpad-dashboard-width   "80%"
    set -g @tpad-dashboard-height  "80%"

    run '${config.xdg.configHome}/tmux/plugins/tpm/tpm'

    # catppuccin leaves status-left/right empty; set after the plugin has loaded.
    set -g status-left-length 100
    set -g status-right-length 100
    set -g status-left "#{E:@catppuccin_status_session} "
    set -g status-right "#{E:@catppuccin_status_date_time}"
  '';
}
