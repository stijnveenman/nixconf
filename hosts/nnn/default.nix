{
  home-manager,
  nixpkgs,
  ...
}:

nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
	          home-manager.nixosModules.home-manager

    {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
	    home-manager.users.stiixxy = {
    home.stateVersion = "26.05";
	    imports = [
    ../../modules/neovim.nix
	    ];
	    programs.bash.enable = true;
  programs.git = {
  enable = true;
  
    settings = {
      user = {
        name  = "Stijn Veenman";
        email = "veenman.stijn@gmail.com";
      };
      init.defaultBranch = "main";
    };
  };


	    };
          }
      ];
    }
