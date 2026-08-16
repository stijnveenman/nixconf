{
  lib,
  pkgs,
  ...
}: {
  home-manager.users.stiixxy = {
    home.stateVersion = "26.05";

    imports = [
      ../../modules/neovim.nix
    ];

    home.username = "stiixxy";
    home.homeDirectory = "/home/stiixxy";

    programs.bash.enable = true;

    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config = {
        common = {
          default = [
            "gtk"
          ];
        };
      };
    };

    programs.niri.settings = {
      prefer-no-csd = true;
      hotkey-overlay = {
        skip-at-startup = true;
      };

      spawn-at-startup = [
        {argv = ["${lib.getExe pkgs.noctalia-shell}"];}
        {argv = ["${lib.getExe pkgs._1password-gui}" "--silent"];}
        {argv = ["${lib.getExe pkgs.pear-desktop}"];}
        {argv = ["${lib.getExe pkgs.discord}"];}
      ];

      layout = {
        gaps = 6;

        default-column-width = {proportion = 1.;};

        preset-column-widths = [
          {proportion = 0.5;}
          {proportion = 2. / 3.;}
        ];

        focus-ring = {
          width = 1;
        };
      };

      input.mouse.natural-scroll = false;
      input.mouse.accel-profile = "flat";
      input.mouse.accel-speed = 1;
      input.touchpad.natural-scroll = false;

      outputs."DP-2" = {
        position = {
          x = 2560;
          y = 0;
        };
      };

      outputs."HDMI-A-1" = {
        position = {
          x = 0;
          y = 0;
        };
      };

      switch-events = {
        lid-close.action.spawn = ["${lib.getExe pkgs.noctalia-shell}" "ipc" "call" "lockScreen" "lock"];
      };

      window-rules = [
        {
          clip-to-geometry = true;
          geometry-corner-radius.bottom-left = 10.;
          geometry-corner-radius.bottom-right = 10.;
          geometry-corner-radius.top-left = 10.;
          geometry-corner-radius.top-right = 10.;
        }
        {
          matches = [
            {
              app-id = "discord";
              at-startup = true;
            }
            {
              app-id = "lom.github.th-ch.youtube_music";
              at-startup = true;
            }
          ];
          default-column-width = {proportion = 0.50;};
          open-on-workspace = "";
          open-focused = false;
        }
      ];

      workspaces."1" = {open-on-output = "DP-1";};
      workspaces."2" = {open-on-output = "DP-1";};
      workspaces."3" = {open-on-output = "DP-1";};
      workspaces."4" = {open-on-output = "DP-1";};
      workspaces."5" = {open-on-output = "DP-1";};
      workspaces."6" = {open-on-output = "DP-1";};
      workspaces."7" = {open-on-output = "HDMI-A-1";};
      workspaces."8" = {open-on-output = "HDMI-A-1";};
      workspaces."9" = {open-on-output = "HDMI-A-1";};
      workspaces.discord = {
        name = "";
        open-on-output = "HDMI-A-1";
      };

      binds = {
        "Mod+W".action.close-window = {};
        "Mod+Return".action.spawn-sh = lib.getExe pkgs.ghostty;
        "Mod+Shift+Slash".action.spawn-sh = "${lib.getExe pkgs._1password-gui} --toggle";
        "Mod+Shift+B".action.spawn = "${lib.getExe pkgs.google-chrome}";
        "Mod+Ctrl+Shift+B".action.spawn-sh = "${lib.getExe pkgs.google-chrome} --restore-last-session";
        "Mod+Shift+T".action.spawn-sh = "${lib.getExe pkgs.todoist-electron}";

        "Mod+Space".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call launcher toggle";
        "Mod+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call sessionMenu toggle";
        "Mod+Shift+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call lockScreen lock";

        "Mod+R".action.switch-preset-column-width = {};
        "Mod+F".action.maximize-column = {};
        "Mod+Equal".action.set-column-width = "+10%";
        "Mod+Minus".action.set-column-width = "-10%";

        "Mod+1".action.focus-workspace = "1";
        "Mod+2".action.focus-workspace = "2";
        "Mod+3".action.focus-workspace = "3";
        "Mod+4".action.focus-workspace = "4";
        "Mod+5".action.focus-workspace = "5";
        "Mod+6".action.focus-workspace = "6";
        "Mod+7".action.focus-workspace = "7";
        "Mod+8".action.focus-workspace = "8";
        "Mod+9".action.focus-workspace = "9";
        "Mod+0".action.focus-workspace = "";

        "Mod+Shift+1".action.move-window-to-workspace = "1";
        "Mod+Shift+2".action.move-window-to-workspace = "2";
        "Mod+Shift+3".action.move-window-to-workspace = "3";
        "Mod+Shift+4".action.move-window-to-workspace = "4";
        "Mod+Shift+5".action.move-window-to-workspace = "5";
        "Mod+Shift+6".action.move-window-to-workspace = "6";
        "Mod+Shift+7".action.move-window-to-workspace = "7";
        "Mod+Shift+8".action.move-window-to-workspace = "8";
        "Mod+Shift+9".action.move-window-to-workspace = "9";
        "Mod+Shift+0".action.move-window-to-workspace = "";

        "Mod+H".action.focus-column-left = {};
        "Mod+Shift+H".action.move-column-left = {};

        "Mod+L".action.focus-column-right = {};
        "Mod+Shift+L".action.move-column-right = {};

        "Mod+Tab".action.focus-monitor-next = {};

        "Mod+Ctrl+H".action.focus-monitor-left = {};
        "Mod+Ctrl+Shift+H".action.move-column-to-monitor-left = {};

        "Mod+Ctrl+L".action.focus-monitor-right = {};
        "Mod+Ctrl+Shift+L".action.move-column-to-monitor-right = {};

        "Mod+J".action.focus-workspace-down = {};
        "Mod+Shift+J".action.move-column-to-workspace-down = {};
        "Mod+Ctrl+Shift+J".action.move-workspace-down = {};

        "Mod+K".action.focus-workspace-up = {};
        "Mod+Shift+K".action.move-column-to-workspace-up = {};
        "Mod+Ctrl+Shift+K".action.move-workspace-up = {};
      };
    };

    programs.direnv.enable = true;
    programs.ghostty = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        theme = "Gruvbox Dark";
      };
    };

    home.packages = with pkgs; [
      noctalia-shell
      todoist-electron
      pear-desktop
      opencode
    ];

    home.file.".config/noctalia/settings.json".source = ./noctalia.json;
    home.file.".cache/noctalia/wallpapers.json" = {
      text = builtins.toJSON {
        defaultWallpaper = pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath;
      };
    };

    programs.discord.enable = true;

    programs.git = {
      enable = true;

      settings = {
        user = {
          name = "Stijn Veenman";
          email = "veenman.stijn@gmail.com";
        };
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {};
      extraConfig = ''
        Host *
            IdentityAgent ~/.1password/agent.sock
      '';
    };
  };
}
