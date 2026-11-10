{
  config,
  lib,
  pkgs,
  ...
}: let
  repoPath = config.my.nixconf.liveRepoPath;
  piSource = path:
    if repoPath == null
    then ../pi/agent + "/${path}"
    else config.lib.file.mkOutOfStoreSymlink "${repoPath}/pi/agent/${path}";
  piDirectory = directory: excluded:
    pkgs.linkFarm "pi-${directory}" (
      map (name: {
        inherit name;
        path = piSource "${directory}/${name}";
      }) (lib.filter (name: !(builtins.elem name excluded))
        (builtins.attrNames (builtins.readDir (../pi/agent + "/${directory}"))))
    );
in {
  imports = [./repo.nix];

  # Keep mutable Pi state in the home directory, separate from configuration.
  # In live mode, adding or removing entries still requires a rebuild.
  home.file = {
    ".pi/agent/settings.json".source = piSource "settings.json";
    ".pi/agent/keybindings.json".source = piSource "keybindings.json";
    ".pi/agent/AGENTS.md".source = piSource "AGENTS.md";
    ".pi/agent/extensions".source = piDirectory "extensions" ["workmux-status.ts"];
    ".pi/agent/skills".source = piDirectory "skills" ["worktree"];
  };
}
