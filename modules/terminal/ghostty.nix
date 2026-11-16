{
  flake.modules.homeManager.ghostty = {
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
        theme = "Catppuccin Mocha";

        font-family = "JetBrainsMono Nerd Font Mono";
        font-size = 12;
        # Disable programming ligatures (e.g. != stays as two glyphs).
        font-feature = ["-calt" "-liga" "-dlig"];

        # Ignore OSC 9;4 progress sequences (pi's working bar).
        progress-style = false;

        # Fully quit Ghostty when the last window closes so reopening starts a
        # fresh process.
        quit-after-last-window-closed = true;

        # Ghostty maps Cmd+Left/Right to Ctrl+A/E by default, and Ctrl+A is the
        # herdr prefix. Send Home/End instead.
        keybind = [
          "super+arrow_left=text:\\x1b[H"
          "super+arrow_right=text:\\x1b[F"
        ];
      };
    };
  };
}
