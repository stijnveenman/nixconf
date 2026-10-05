{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    pi.url = "github:earendil-works/pi/stable";
    pi.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    niri.url = "github:sodiboo/niri-flake";

    workmux.url = "github:raine/workmux";
    workmux.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: {
    homeConfigurations."stiixxy" = import ./hosts/stiixxy inputs;
    homeConfigurations."sv" = import ./hosts/macbook inputs;

    nixosConfigurations."nnn" = import ./hosts/nnn inputs;
  };
}
