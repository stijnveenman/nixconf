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
    repoPath = config.my.nixconf.liveRepoPath;
    piSource = path:
      if repoPath == null
      then ../../pi/agent + "/${path}"
      else config.lib.file.mkOutOfStoreSymlink "${repoPath}/pi/agent/${path}";
    piPackage = import ./_lib/pi-package.nix {inherit lib pkgs;};
    piDirectory = directory: excluded: extra:
      pkgs.linkFarm "pi-${directory}" (
        map (name: {
          inherit name;
          path = piSource "${directory}/${name}";
        }) (lib.filter (name: !(builtins.elem name excluded))
          (builtins.attrNames (builtins.readDir (../../pi/agent + "/${directory}"))))
        ++ extra
      );
  in {
    imports = [flakeModules.homeManager.repo];

    # Pi comes from Nix, so its self-update notice is not actionable.
    home.sessionVariables.PI_SKIP_VERSION_CHECK = "1";

    # Keep mutable Pi state in the home directory, separate from configuration.
    # In live mode, adding or removing entries still requires a rebuild.
    home.file = {
      ".pi/agent/settings.json".source = piSource "settings.json";
      ".pi/agent/keybindings.json".source = piSource "keybindings.json";
      ".pi/agent/AGENTS.md".source = piSource "AGENTS.md";
      ".pi/agent/watch-pr.json".source = piSource "watch-pr.json";
      ".pi/agent/extensions".source = piDirectory "extensions" [] [
        (piPackage {src = inputs.pi-web-access;})
        (piPackage {
          src = inputs.pi-subagents;
          hash = "sha256-405Bq+e+p+eE0KLQmy7Wox5q5fwcmAAcmQG0MdWXyEE=";
        })
        {
          # Same asset `herdr integration install pi` writes, which fails on the read-only store dir.
          name = "herdr-agent-state.ts";
          path = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
        }
      ];
      ".pi/agent/skills".source = piDirectory "skills" ["worktree"] [];
    };
  };
}
