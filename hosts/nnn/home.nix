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
      ];

      binds = {
        "Mod+Return".action.spawn-sh = lib.getExe pkgs.ghostty;
        "Mod+W".action.close-window = {};
        "Mod+Space".action.spawn-sh = "${lib.getExe pkgs.noctalia-shell} ipc call launcher toggle";
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
