# Private Attic binary cache, reachable only over Tailscale, with TLS from
# Tailscale Serve. CI pushes every host's build to it
# (.github/workflows/build.yml); every host pulls from it without a token.
let
  url = "https://atticd.mermaid-pomfret.ts.net/mycache";
  # From `attic cache info mycache`. Set to null to disable the cache.
  publicKey = "mycache:+HYAd5jlos2i1qZwfaj0qEYbkbfqcwULY5WJ0FhL9D0=";

  enabled = publicKey != null;
  # Off the tailnet the host doesn't resolve; give up quickly instead of
  # stalling every build on the default connect timeout.
  connectTimeout = 5;
in {
  flake.modules.nixos.attic-cache = {lib, ...}: {
    nix.settings = lib.mkIf enabled {
      substituters = [url];
      trusted-public-keys = [publicKey];
      connect-timeout = connectTimeout;
    };
  };

  # Standalone home-manager writes ~/.config/nix/nix.conf. The Nix daemon only
  # honours these substituters when the user is in `trusted-users`.
  flake.modules.homeManager.attic-cache = {
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf enabled {
      nix.package = lib.mkDefault pkgs.nix;
      nix.settings = {
        extra-substituters = [url];
        extra-trusted-public-keys = [publicKey];
        connect-timeout = connectTimeout;
      };
    };
  };
}
