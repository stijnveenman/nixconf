# Noctalia shell (bar, launcher, lock screen) used with niri.
{
  flake.modules.homeManager.nnn-noctalia = {
    config,
    pkgs,
    ...
  }: {
    xdg.configFile."noctalia/config.toml".source = (pkgs.formats.toml {}).generate "noctalia-config.toml" {
      accessibility.ui_scale = 0.85;
      shell.font_family = "JetBrainsMono NFM";
      # Reboot/shut down with --no-wall: plain `systemctl reboot` re-enables
      # logind wall messages ("Broadcast message from ...") on every call, which
      # then flash on the console as the session closes. Listing actions
      # replaces the default list, so all five defaults are repeated here.
      shell.session.actions = let
        action = name: shortcut: extra:
          {
            action = name;
            inherit shortcut;
          }
          // extra;
      in [
        # Lock with hyprlock (modules/desktop/lockscreen) instead of noctalia's
        # own lock screen; hypridle locks before suspend.
        (action "lock" "1" {command = config.my.lockscreen.command;})
        (action "logout" "2" {})
        (action "lock_and_suspend" "3" {command = "systemctl suspend";})
        (action "reboot" "4" {command = "systemctl reboot --no-wall";})
        (action "shutdown" "5" {
          command = "systemctl poweroff --no-wall";
          variant = "destructive";
        })
      ];
      bar.default = {
        font_family = "JetBrainsMono NFM";
        margin_ends = 0;
        start = ["workspaces"];
        end = ["media" "tray" "notifications" "network" "bluetooth" "volume" "brightness" "battery" "session"];
      };
      # hypridle locks before suspend instead.
      lockscreen.lock_before_suspend = false;
      theme.builtin = "Catppuccin";
      widget.workspaces = {
        type = "workspaces";
        show_labels = true;
        label_source = "name";
        hide_when_empty = true;
      };
      wallpaper.default.path = "${pkgs.nixos-artwork.wallpapers.nineish-catppuccin-mocha-alt.gnomeFilePath}";
    };
  };
}
