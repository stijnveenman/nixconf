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
        defaults.prApproveComment = "";
        repoPaths = {
          "schiphol-ac/airport-control" = "~/Documents/airport-control";
          "stijnveenman/nixconf" = "~/Documents/nixconf";
        };
        prSections = [
          {
            title = "My Pull Requests";
            filters = "is:open author:@me";
          }
          {
            title = "Needs My Review";
            # user-review-requested only matches requests to me, not my teams.
            filters = "is:open user-review-requested:@me";
          }
          {
            title = "Dependency Updates";
            filters = "is:open archived:false (author:app/dependabot OR author:app/renovate)";
          }
          {
            title = "Involved";
            filters = "is:open involves:@me -author:@me -user-review-requested:@me";
          }
        ];
        keybindings = {
          universal = [
            {
              key = "o";
              builtin = "openGithub";
            }
          ];
          prs = [
            {
              key = "c";
              name = "checkout with wt start";
              command = "cd {{.RepoPath}} && wt start --pr {{.PrNumber}}";
            }
            {
              key = "d";
              name = "diff in tuicr";
              # tuicr comes from the tuicr module (patched build), so use PATH.
              command = "tuicr pr {{.RepoName}}#{{.PrNumber}}";
            }
          ];
        };
      };
    };
  };
}
