{
  flake.modules.homeManager.hunk = {pkgs, ...}: let
    toml = pkgs.formats.toml {};
  in {
    home.packages = [pkgs.hunk];

    # hunk derives its panel colors by blending the foreground into the
    # background, which makes the left pane lighter than Ghostty's Catppuccin
    # Mocha. Override them with the palette values (base, mantle, surface0).
    xdg.configFile."hunk/config.toml".source = toml.generate "hunk-config.toml" {
      theme = "mocha-flat";
      mode = "auto";
      line_numbers = true;
      wrap_lines = true;
      hunk_headers = false;
      menu_bar = true;
      agent_notes = false;
      copy_decorations = false;
      cursor_line = "row";
      prompt_save_view_preferences = false;

      themes.mocha-flat = {
        base = "catppuccin-mocha";
        panel = "#1e1e2e";
        panelAlt = "#181825";
        border = "#313244";
      };
    };
  };
}
