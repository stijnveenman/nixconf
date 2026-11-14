{
  lib,
  pkgs,
  inputs,
  ...
}: {
  home-manager.users.stiixxy = {config, ...}: {
    home.stateVersion = "26.05";

    imports = [
      ../../modules/neovim.nix
      ../../modules/git.nix
      ../../modules/cli-tools.nix
      ../../modules/tuicr.nix
      ../../modules/ghostty.nix
      ../../modules/opencode.nix
      ../../modules/pi.nix
      ../../modules/herdr
      ../../modules/zsh.nix
      ../../modules/lazygit.nix
      ../../modules/askpass
    ];

    my.git.userEmail = "veenman.stijn@gmail.com";

    programs.git = {
      signing = {
        format = "ssh";
        key = lib.mkForce "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
      settings.gpg.ssh = {
        program = lib.getExe' pkgs.openssh "ssh-keygen";
        allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
      };
    };

    xdg.configFile."git/allowed_signers".text = ''
      ${config.my.git.userEmail} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQN61R7viARkAAIZF8JWmvXfs49/3l1BL4ozDMTadt2
    '';
    my.nixconf.liveRepoPath = "/home/stiixxy/nixconf";

    home.username = "stiixxy";
    home.homeDirectory = "/home/stiixxy";

    programs.bash.enable = true;

    programs.nh = {
      enable = true;
      homeFlake = "/home/stiixxy/nixconf";
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep=10";
      };
    };

    home.sessionVariables.NIX_PATH = "nixpkgs=${inputs.nixpkgs}";

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
        {argv = ["${lib.getExe pkgs.noctalia}"];}
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
        lid-close.action.spawn = ["${lib.getExe pkgs.noctalia}" "msg" "session" "lock"];
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

        "Mod+Space".action.spawn-sh = "${lib.getExe pkgs.noctalia} msg panel-toggle launcher";
        "Mod+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia} msg panel-toggle session";
        "Mod+Shift+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia} msg session lock";

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
      wallpaper.default.path = "${pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath}";
    };

    home.packages = with pkgs; [
      noctalia
      todoist-cli
      _1password-cli
      git-crypt
      hunk
      nixd
      alejandra
      nerd-fonts.jetbrains-mono
      inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
      todoist-electron
      pear-desktop
    ];

    programs.ghostty = {
      # Host-specific ghostty settings (shared theme/font/package live in
      # ../../modules/ghostty.nix). These mirror the macbook host but avoid
      # auto-launching a specific command on startup.
      settings = {
        # Fully quit Ghostty when the last window closes so reopening starts a
        # fresh process.
        quit-after-last-window-closed = true;
      };
    };
    programs.discord.enable = true;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*".IdentityFile = "~/.ssh/id_ed25519";
      extraConfig = ''
        Host *
            IdentityAgent ~/.1password/agent.sock
      '';
    };
  };
}
