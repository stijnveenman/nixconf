inputs @ {
  home-manager,
  nixpkgs,
  workmux,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {inherit inputs workmux;};
    modules = [
      ./home.nix
      ../../modules/neovim.nix
      ../../modules/workmux
    ];
  }
