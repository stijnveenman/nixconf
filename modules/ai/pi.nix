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

    # The extension reads `config.json` from, and logs into, its own directory,
    # which is in the store: add the config and a symlink to a writable logs dir.
    permissionSystemPackage = pi.package {
      src = inputs.pi-packages;
      subdir = "packages/pi-permission-system";
      hash = "sha256-M0isiVhotrrs3yBuS5RWZIoh+OOieCgz5LrL7RMLMoY=";
    };
    permissionSystem = {
      inherit (permissionSystemPackage) name;
      path = pkgs.runCommand "pi-permission-system" {} ''
        mkdir $out
        for entry in ${permissionSystemPackage.path}/* ${permissionSystemPackage.path}/.[!.]*; do
          [ -e "$entry" ] && ln -s "$entry" $out/
        done
        ln -s ${../../pi/agent/pi-permission-system.json} $out/config.json
        ln -s ${config.home.homeDirectory}/.pi/agent/logs/pi-permission-system $out/logs
      '';
    };
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
      # The extension writes logs under its own (read-only) directory; point them here.
      ".pi/agent/logs/pi-permission-system/.keep".text = "";
      ".pi/agent/watch-pr.json".source = pi.source "watch-pr.json";
      ".pi/agent/extensions".source = pi.directory "extensions" [] [
        (pi.package {src = inputs.pi-web-access;})
        (pi.package {
          src = inputs.pi-packages;
          subdir = "packages/pi-subagents";
          hash = "sha256-g19jdpuToV/Mf/QvlPKTEXtz939s16X2ewXWrkhaRuI=";
        })
        permissionSystem
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
