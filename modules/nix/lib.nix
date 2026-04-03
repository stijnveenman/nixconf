{
  lib,
  inputs,
  ...
}: {
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = {};
  };

  config.flake.lib = {
    mkHome = system: name: {
      ${name} = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        modules = [
          inputs.self.homeModules.${name}
          inputs.self.homeModules.nh
          {
            nixpkgs.config.allowUnfree = true;
            programs.bash.enable = true;

            home = {
              username = name;
              homeDirectory = "/home/${name}";
              stateVersion = "25.11";
            };
          }
        ];
      };
    };
  };
}
