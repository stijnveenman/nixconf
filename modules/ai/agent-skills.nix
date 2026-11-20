# Skills shared by every coding agent. Pi reads `~/.agents/skills` natively;
# Claude Code only reads `~/.claude/skills`, so it gets the same entries.
{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.agent-skills = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # `worktree` was never linked for Pi either; keep it out.
    excluded = ["worktree"];
    skills = pkgs.linkFarm "agent-skills" (
      map (name: {
        inherit name;
        path = config.lib.nixconf.source "agents/skills/${name}";
      }) (lib.filter (name: !(builtins.elem name excluded))
        (builtins.attrNames (builtins.readDir ../../agents/skills)))
    );
  in {
    imports = [flakeModules.homeManager.repo];

    home.file = {
      ".agents/skills".source = skills;
      ".claude/skills".source = skills;
    };
  };
}
