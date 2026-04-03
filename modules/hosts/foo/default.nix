{inputs, ...}: {
  flake.homeConfigurations = inputs.self.lib.mkHome "x86_64-linux" "stiixxy";
}
