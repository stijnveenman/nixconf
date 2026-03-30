{
  self,
  inputs,
  ...
}: {
  flake.homeConfigurations.omarchy = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {system = "x86_64-linux";};
    modules = [
      {
        home.username = "stiixxy";
        home.homeDirectory = "/home/stiixxy/";
        home.stateVersion = "25.11";
      }
    ];
  };
}
