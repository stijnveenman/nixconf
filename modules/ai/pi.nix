{
  config,
  inputs,
  ...
}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.pi = {
    config,
    lib,
    pkgs,
    ...
  }: let
    pi = config.lib.pi;
  in {
    imports = [
      flakeModules.homeManager.repo
      flakeModules.homeManager.pi-lib
    ];

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
        (pi.package {
          src = inputs.pi-permission-system;
          nodeModules.jsonc-parser = pkgs.fetchzip {
            url = "https://registry.npmjs.org/jsonc-parser/-/jsonc-parser-3.3.1.tgz";
            hash = "sha256-eZb4Epz0UsTTaSstqBl46Sy/KRyKaJ+vBUJ92/6wsZY=";
          };
        })
        {
          name = "herdr-agent-state.ts";
          path = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
        }
      ];
      ".pi/agent/agents".source = pi.directory "agents" [".gitkeep"] [];
      ".pi/agent/skills".source = pi.directory "skills" ["worktree"] [];
    };
  };
}
