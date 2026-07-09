{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    niri.url = "github:sodiboo/niri-flake";
  };

  outputs = inputs: {
    homeConfigurations."stiixxy" = import ./hosts/stiixxy inputs;
    homeConfigurations."sv" = import ./hosts/macbook inputs;

    nixosConfigurations."nnn" = import ./hosts/nnn inputs;
    nixosConfigurations."utm" = import ./hosts/utm inputs;
  };
}
