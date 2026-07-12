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

    programs.niri.settings = {
      spawn-at-startup = [
        {argv = ["${lib.getExe pkgs.noctalia-shell}"];}
        {argv = ["${lib.getExe pkgs._1password-gui} --silent"];}
      ];

      binds = {
        "Mod+W".action.close-window = {};
        "Mod+Return".action.spawn-sh = lib.getExe pkgs.ghostty;
        "Mod+Shift+Slash".action.spawn-sh = "${lib.getExe pkgs._1password-gui} --toggle";

        "Mod+Space".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call launcher toggle";
        "Mod+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call sessionMenu toggle";
        "Mod+Shift+Grave".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call lockScreen lock";

        "Mod+N".action.focus-workspace-down = {};
        "Mod+P".action.focus-workspace-up = {};

        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+6".action.focus-workspace = 6;
        "Mod+7".action.focus-workspace = 7;
        "Mod+8".action.focus-workspace = 8;
        "Mod+9".action.focus-workspace = 9;
        "Mod+0".action.focus-workspace = 0;

        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
        "Mod+Shift+4".action.move-window-to-workspace = 4;
        "Mod+Shift+5".action.move-window-to-workspace = 5;
        "Mod+Shift+6".action.move-window-to-workspace = 6;
        "Mod+Shift+7".action.move-window-to-workspace = 7;
        "Mod+Shift+8".action.move-window-to-workspace = 8;
        "Mod+Shift+9".action.move-window-to-workspace = 9;
        "Mod+Shift+0".action.move-window-to-workspace = 0;

        "Mod+H".action.focus-column-left = {};
        "Mod+Shift+H".action.move-column-left = {};

        "Mod+L".action.focus-column-right = {};
        "Mod+Shift+L".action.move-column-right = {};
      };
    };

    programs.ghostty = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        theme = "Gruvbox Dark";
      };
    };

    home.packages = with pkgs; [
      noctalia-shell
    ];

    home.file.".config/noctalia/settings.json".source = ./noctalia.json;

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
