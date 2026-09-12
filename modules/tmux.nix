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
    unbind r
    bind r source-file ${config.xdg.configHome}/tmux/tmux.conf

    set -g prefix C-s
    set -g mouse on

    set -g @plugin 'tmux-plugins/tpm'

    run ${config.xdg.configHome}/tmux/plugins/tpm/tpm
  '';
}
