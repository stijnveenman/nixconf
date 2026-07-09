{...}: {
  home-manager.users.stiixxy = {
    home.stateVersion = "26.05";

    imports = [
      ../../modules/neovim.nix
    ];

    home.username = "stiixxy";
    home.homeDirectory = "/home/stiixxy";

    programs.bash.enable = true;

    programs.niri.settings = {};

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
