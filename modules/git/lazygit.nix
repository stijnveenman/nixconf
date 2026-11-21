{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.lazygit = {
    imports = [flakeModules.homeManager.catppuccin];

    catppuccin.lazygit.enable = true;

    programs.lazygit = {
      enable = true;
      settings = {
        quitOnTopLevelReturn = true;
        git.overrideGpg = false;

        # Disable all background tasks for maximum speed / minimal git activity.
        git.autoFetch = false; # no periodic `git fetch`
        git.fetchAll = false; # don't pass --all to git fetch
        git.autoRefresh = false; # no periodic file/submodule refresh
        git.autoDetectExternalChanges = false; # no periodic repo polling
        update.method = "never"; # no periodic update checks

        gui = {
          # Remove the submodules and tags panels.
          sidePanels = [
            ["status"]
            ["files" "worktrees"]
            ["branches" "remotes"]
            ["commits" "reflog"]
            ["stash"]
          ];
        };
      };
    };
  };
}
