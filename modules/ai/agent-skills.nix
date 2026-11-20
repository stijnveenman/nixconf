# Skills shared by every coding agent. Pi reads `~/.agents/skills` natively;
# Claude Code only reads `~/.claude/skills`, so it gets the same entries. Each
# skill is linked on its own so the directories can hold unmanaged skills too
# (Claude cloud sessions ship their own in `~/.claude/skills`).
{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.agent-skills = {
    config,
    lib,
    ...
  }: let
    # `worktree` was never linked for Pi either; keep it out.
    excluded = ["worktree"];
    names =
      lib.filter (name: !(builtins.elem name excluded))
      (builtins.attrNames (builtins.readDir ../../agents/skills));
    links = dir:
      lib.listToAttrs (map (name: {
          name = "${dir}/${name}";
          value.source = config.lib.nixconf.source "agents/skills/${name}";
        })
        names);
  in {
    imports = [flakeModules.homeManager.repo];

    home.file = links ".agents/skills" // links ".claude/skills";
  };
}
