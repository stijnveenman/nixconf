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
      input.keyboard.xkb.layout = "us,ua";

      layout.gaps = 5;

      binds = {
        "Mod+Return".spawn-sh = lib.getExe pkgs.kitty;
        "Mod+Q".close-window = null;
        "Mod+S".spawn-sh = "${lib.getExe pkgs.noctalia} ipc call launcher toggle";
      };
    };

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
