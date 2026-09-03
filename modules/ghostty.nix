{
  config,
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  useZsh = config.programs.zsh.enable;
  useBash = config.programs.bash.enable;
in {
  programs.ghostty = {
    enable = true;

    # nixpkgs ghostty is Linux-only; on aarch64-darwin the app is installed via
    # `brew install --cask ghostty`, so home-manager manages config only (no
    # package) there. On Linux use the nixpkgs package.
    package = lib.mkIf isDarwin null;

    enableZshIntegration = lib.mkIf useZsh true;
    enableBashIntegration = lib.mkIf useBash true;

    settings = {
      theme = "Gruvbox Dark";

      font-family = "JetBrainsMono Nerd Font Mono";
      font-size = 12;
      # Disable programming ligatures (e.g. != stays as two glyphs).
      font-feature = ["-calt" "-liga" "-dlig"];
    };
  };
}
