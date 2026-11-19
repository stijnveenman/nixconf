{
  flake.modules.homeManager.gh-dash = {
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
