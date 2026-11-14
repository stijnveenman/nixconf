{...}: {
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
        # Catppuccin Mocha (blue accent).
        theme = {
          activeBorderColor = ["#89b4fa" "bold"];
          inactiveBorderColor = ["#a6adc8"];
          optionsTextColor = ["#89b4fa"];
          selectedLineBgColor = ["#313244"];
          cherryPickedCommitBgColor = ["#45475a"];
          cherryPickedCommitFgColor = ["#89b4fa"];
          unstagedChangesColor = ["#f38ba8"];
          defaultFgColor = ["#cdd6f4"];
          searchingActiveBorderColor = ["#f9e2af"];
          branchColorPatterns.config = "#11aaff";
        };

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
}
