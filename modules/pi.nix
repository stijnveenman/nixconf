{
  config,
  lib,
  pkgs,
  ...
}: let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  repoPath =
    if isDarwin
    then "/Users/${config.home.username}/Documents/nixconf"
    else "/home/${config.home.username}/nixconf";
  piPath = "${repoPath}/pi/agent";
  liveLink = path: config.lib.file.mkOutOfStoreSymlink "${piPath}/${path}";
  liveDirectory = directory: excluded:
    pkgs.linkFarm "pi-${directory}" (
      map (name: {
        inherit name;
        path = liveLink "${directory}/${name}";
      }) (lib.filter (name: !(builtins.elem name excluded))
        (builtins.attrNames (builtins.readDir (../pi/agent + "/${directory}"))))
    );
in {
  # Keep Pi's mutable state (.pi/agent/auth.json, sessions, npm/, etc.) in the
  # home directory, while linking the configuration that is safe to edit in
  # this repository. These links intentionally do not need a Home Manager
  # rebuild after the initial activation. Adding or removing skill/extension
  # entries requires a rebuild, but their contents remain live-linked.
  home.file = {
    ".pi/agent/settings.json".source = liveLink "settings.json";
    ".pi/agent/keybindings.json".source = liveLink "keybindings.json";
    ".pi/agent/AGENTS.md".source = liveLink "AGENTS.md";
    # Keep existing entries live, while omitting the retired workmux workflow
    # only when this Home Manager generation is activated.
    ".pi/agent/extensions".source = liveDirectory "extensions" ["workmux-status.ts"];
    ".pi/agent/skills".source = liveDirectory "skills" ["worktree"];
  };
}
