# Noctalia shell (bar, launcher, lock screen) used with niri.
{
  flake.modules.homeManager.nnn-noctalia = {pkgs, ...}: {
    xdg.configFile."noctalia/config.toml".source = (pkgs.formats.toml {}).generate "noctalia-config.toml" {
      accessibility.ui_scale = 0.85;
      shell.font_family = "JetBrainsMono NFM";
      bar.default = {
        font_family = "JetBrainsMono NFM";
        margin_ends = 0;
        start = ["workspaces"];
        end = ["media" "tray" "notifications" "network" "bluetooth" "volume" "brightness" "battery" "session"];
      };
      theme.builtin = "Catppuccin";
      widget.workspaces = {
        type = "workspaces";
        show_labels = true;
        label_source = "name";
        hide_when_empty = true;
      };
      wallpaper.default.path = "${pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath}";
    };
  };
}
