{
  pkgs,
  config,
  ...
}: {
  home.packages = [pkgs.tmux pkgs.reattach-to-user-namespace];
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
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
    set -g prefix C-s
    set -g mouse on

    unbind r
    bind r source-file ${config.xdg.configHome}/tmux/tmux.conf

    bind C-s 'send-keys C-s'

    bind v split-pane -h -c "#{pane_current_path}"
    bind - split-pane -v -c "#{pane_current_path}"

    bind n next-window
    bind p previous-window
    bind c new-window

    bind g display-popup -w 80% -h 80% lazygit

    set-option -g pane-border-status top
    set-option -g pane-border-lines heavy
    set-option -g pane-border-indicators off
    set-option -g pane-border-format ""

    # --- Sensible defaults
    set -s escape-time 0
    set -g history-limit 50000
    set -g display-time 4000
    set -g status-interval 5
    # (OS X) Fix pbcopy/pbpaste for old tmux versions (pre 2.6)
    set -g default-command "reattach-to-user-namespace -l $SHELL"
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",*:RGB"
    set -g status-keys emacs
    set -g focus-events on
    set -g extended-keys on
    set -g extended-keys-format csi-u
    setw -g aggressive-resize on

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
