{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.gh-dash = {
    imports = [flakeModules.homeManager.catppuccin];

    catppuccin.gh-dash.enable = true;

    programs.gh-dash = {
      enable = true;
      settings = {
        confirmQuit = false;
        # Show all PRs/issues, not only those of the repo dash starts in.
        smartFilteringAtLaunch = false;
        keybindings = {
          # o reviews in tuicr; opening in the browser moves to O. In the
          # repo view O would shadow create PR, so that moves to o.
          universal = [
            {
              key = "O";
              builtin = "openGithub";
            }
          ];
          branches = [
            {
              key = "o";
              builtin = "createPr";
            }
          ];
          notifications = [
            {
              key = "O";
              builtin = "open";
            }
          ];
          prs = [
            {
              key = "o";
              name = "review in tuicr";
              # tuicr comes from the tuicr module (patched build), so use PATH.
              command = "tuicr pr {{.RepoName}}#{{.PrNumber}}";
            }
          ];
        };
      };
    };
  };
}
