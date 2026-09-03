{
  config,
  pkgs,
  lib,
  ...
}: let
  useZsh = config.programs.zsh.enable;
  useBash = config.programs.bash.enable;
in {
  home.packages = [
    # Utils shared across hosts.
    pkgs.jless
    pkgs.ripgrep
    pkgs.jq
    pkgs.fzf
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = lib.mkIf useZsh true;
    enableBashIntegration = lib.mkIf useBash true;
    nix-direnv.enable = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = lib.mkIf useZsh true;
    enableBashIntegration = lib.mkIf useBash true;
    flags = ["--disable-up-arrow"];
    settings = {
      inline_height = 15;
    };
  };

  programs.gh = {
    enable = true;
    extensions = [pkgs.gh-poi];
  };
}
