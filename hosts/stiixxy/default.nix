inputs @ {
  home-manager,
  nixpkgs,
  ...
}:
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages."x86_64-linux";
  extraSpecialArgs = {inherit inputs;};
  modules = [
    ./home.nix
    ../../modules/neovim.nix
    ../../modules/opencode.nix
  ];
}
