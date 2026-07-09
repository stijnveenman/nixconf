{...}: {
  home.stateVersion = "26.05";

  imports = [
    ../../modules/neovim.nix
  ];

  home.username = "stiixxy";
  home.homeDirectory = "/home/stiixxy";

  programs.bash.enable = true;

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
}
