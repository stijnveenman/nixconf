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
        keybindings.prs = [
          {
            key = "T";
            name = "review in tuicr";
            # tuicr comes from the tuicr module (patched build), so use PATH.
            command = "tuicr pr {{.RepoName}}#{{.PrNumber}}";
          }
        ];
      };
    };
  };
}
