{
  flake.modules.homeManager.cli-tools = {
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
      pkgs.python3
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
      extensions = [pkgs.gh-poi pkgs.gh-stack];
    };

    # Catppuccin Mocha (blue accent), from github.com/catppuccin/gh-dash.
    programs.gh-dash = {
      enable = true;
      settings.theme.colors = {
        text = {
          primary = "#cdd6f4";
          secondary = "#89b4fa";
          inverted = "#11111b";
          faint = "#bac2de";
          warning = "#f9e2af";
          success = "#a6e3a1";
          error = "#f38ba8";
        };
        background.selected = "#313244";
        border = {
          primary = "#89b4fa";
          secondary = "#45475a";
          faint = "#313244";
        };
      };
    };
  };
}
