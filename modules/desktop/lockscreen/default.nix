{
  # Lock screen: hyprlock styled like the SDDM login screen (modules/desktop/
  # greeter), NixOS logo with a password prompt below it. hypridle locks before
  # suspend. Other modules lock with `config.my.lockscreen.command`.
  # Needs `security.pam.services.hyprlock` on the NixOS side.
  flake.modules.homeManager.lockscreen = {
    config,
    lib,
    pkgs,
    ...
  }: let
    magick = "${pkgs.imagemagick}/bin/magick";
    logo = "${pkgs.nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png";
    font = "JetBrainsMono Nerd Font";

    # Same layout as the login screen: logo a quarter of the screen height,
    # centred 1/16 of the height above the middle. Baked into the background so
    # it scales with every monitor.
    background = pkgs.runCommand "lockscreen-background.png" {} ''
      ${magick} -size 2560x1600 xc:'#121217' \
        \( ${logo} -resize 400x400 \) \
        -gravity center -geometry +0-100 -composite $out
    '';

    lock = pkgs.writeShellApplication {
      name = "lock-screen";
      runtimeInputs = [config.programs.hyprlock.package pkgs.procps];
      text = builtins.readFile ./scripts/lock.sh;
    };
  in {
    options.my.lockscreen.command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.getExe lock;
      description = "Command that locks the session.";
    };

    config = {
      home.packages = [lock];

      programs.hyprlock = {
        enable = true;
        settings = {
          general = {
            hide_cursor = true;
            grace = 0;
          };
          animations.enabled = false;

          background = [
            {
              path = "${background}";
              color = "rgb(121217)";
            }
          ];

          # Sizes and positions are percentages of the monitor, matching the
          # login screen's proportions (field 0.35 x height wide, below the logo).
          input-field = [
            {
              size = "21%, 4.6%";
              position = "0, -12.7%";
              halign = "center";
              valign = "center";
              rounding = -1;
              outline_thickness = 2;
              outer_color = "rgb(7ebae4)";
              inner_color = "rgb(2a2d36)";
              font_color = "rgb(e0e0e6)";
              font_family = font;
              check_color = "rgb(7ebae4)";
              fail_color = "rgb(e78284)";
              fail_text = "Wrong password";
              placeholder_text = "<span foreground='##6c6f7e'>Password</span>";
              fade_on_empty = false;
              dots_center = true;
              dots_size = 0.2;
              dots_spacing = 0.3;
              shadow_passes = 0;
            }
          ];
        };
      };

      services.hypridle = {
        enable = true;
        settings.general = {
          lock_cmd = lib.getExe lock;
          before_sleep_cmd = lib.getExe lock;
        };
      };
    };
  };
}
