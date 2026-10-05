inputs @ {
  home-manager,
  nixpkgs,
  pi,
  workmux,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {inherit inputs pi workmux;};
    modules = [
      ./home.nix
      ../../modules/neovim.nix
      ../../modules/workmux
    ];
  }
