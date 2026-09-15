{
  home-manager,
  nixpkgs,
  treehouse,
  worktrunk,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit treehouse worktrunk;
    };
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }
