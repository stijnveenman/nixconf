{
  pkgs,
  config,
  ...
}: {
  home.packages = [pkgs.tmux];

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
    unbind r
    bind r source-file ${config.xdg.configHome}/tmux/tmux.conf

    set -g prefix C-s
    set -g mouse on

    # --- Sensible defaults
    set -s escape-time 0
    set -g history-limit 50000
    set -g display-time 4000
    set -g status-interval 5
    # (OS X) Fix pbcopy/pbpaste for old tmux versions (pre 2.6)
    set -g default-command "reattach-to-user-namespace -l $SHELL"
    set -g default-terminal "screen-256color"
    set -g status-keys emacs
    set -g focus-events on
    setw -g aggressive-resize on

    set -g @plugin 'tmux-plugins/tpm'

    # --- plugins
    set -g @plugin 'egel/tmux-gruvbox'
    set -g @tmux-gruvbox 'dark'
    set-option -g status-position top
    set -g @tmux-gruvbox-right-status-z ' '

    run '${config.xdg.configHome}/tmux/plugins/tpm/tpm'
  '';
}
