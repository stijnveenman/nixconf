{
  config,
  inputs,
  ...
}: let
  flakeModules = config.flake.modules;
  piLib = config.flake.lib.pi;
in {
  flake.modules.homeManager.pi = {
    config,
    lib,
    pkgs,
    ...
  }: let
    pi = piLib.mkHelpers {inherit config lib pkgs;};
  in {
    imports = [flakeModules.homeManager.repo];

    # Pi comes from Nix, so its self-update notice is not actionable.
    home.sessionVariables.PI_SKIP_VERSION_CHECK = "1";

    # Keep mutable Pi state in the home directory, separate from configuration.
    # In live mode, adding or removing entries still requires a rebuild.
    home.file = {
      ".pi/agent/settings.json".source = pi.source "settings.json";
      ".pi/agent/keybindings.json".source = pi.source "keybindings.json";
      ".pi/agent/AGENTS.md".source = pi.source "AGENTS.md";
      ".pi/agent/watch-pr.json".source = pi.source "watch-pr.json";
      ".pi/agent/extensions".source = pi.directory "extensions" [] [
        (pi.package {src = inputs.pi-web-access;})
        (pi.package {
          src = inputs.pi-subagents;
          hash = "sha256-405Bq+e+p+eE0KLQmy7Wox5q5fwcmAAcmQG0MdWXyEE=";
        })
        {
          # Same asset `herdr integration install pi` writes, which fails on the read-only store dir.
          name = "herdr-agent-state.ts";
          path = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
        }
      ];
      ".pi/agent/skills".source = pi.directory "skills" ["worktree"] [];
    };
  };
}
