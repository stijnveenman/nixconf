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
      ".pi/agent/models.json".source = pi.source "models.json";
      ".pi/agent/keybindings.json".source = pi.source "keybindings.json";
      ".pi/agent/AGENTS.md".source = pi.source "AGENTS.md";
      ".pi/agent/watch-pr.json".source = pi.source "watch-pr.json";
      ".pi/agent/extensions".source = pi.directory "extensions" [] [
        (pi.package {src = inputs.pi-web-access;})
        (pi.package {
          src = inputs.pi-packages;
          subdir = "packages/pi-subagents";
          hash = "sha256-7apiyaAmbr5D2US6mZc+A9xIksP8TdKwwlJi4WIaSEs=";
        })
        {
          name = "herdr-agent-state.ts";
          path = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
        }
      ];
      ".pi/agent/agents".source = pi.directory "agents" [".gitkeep"] [];
    };
  };
}
