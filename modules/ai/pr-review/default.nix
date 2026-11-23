# gh-dash ctrl+o: review the selected PR with Pi in a Herdr tab, next to tuicr.
{inputs, ...}: {
  flake.modules.homeManager.pr-review = {
    config,
    lib,
    pkgs,
    ...
  }: let
    herdr = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    git = lib.getExe pkgs.git;
    jq = lib.getExe pkgs.jq;

    # tuicr comes from the tuicr module (patched build), so it resolves on PATH.
    prReview = pkgs.writeShellScript "pr-review" ''
      herdr=${lib.escapeShellArg herdr}
      git=${lib.escapeShellArg git}
      jq=${lib.escapeShellArg jq}
      model=${lib.escapeShellArg config.my.prReview.model}
      ${builtins.readFile ./scripts/pr-review.sh}
    '';
  in {
    options.my.prReview.model = lib.mkOption {
      type = lib.types.str;
      default = "github-copilot/claude-opus-5.5";
      description = "Pi `--model` pattern for PR reviews (a `:<thinking>` suffix is allowed).";
    };

    config = {
      home.packages = [
        (pkgs.runCommand "pr-review" {} "install -Dm755 ${prReview} $out/bin/pr-review")
      ];

      programs.gh-dash.settings.keybindings.prs = [
        {
          key = "ctrl+o";
          name = "review with pi";
          command = "${prReview} {{.RepoName}} {{.PrNumber}}";
        }
      ];
    };
  };
}
