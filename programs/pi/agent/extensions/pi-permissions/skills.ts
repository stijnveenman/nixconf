import { isAbsolute, relative } from "node:path";

export type SkillRef = { name: string; baseDir: string };

const SKILL_COMMAND = /^\/skill:(\S+)/;

/** The skill `/skill:name` input invokes, if any. */
export function skillCommand(text: string): string | undefined {
  return SKILL_COMMAND.exec(text.trimStart())?.[1];
}

/** The skill whose directory contains `absolutePath`, so reading its files counts as using it. */
export function skillAt(absolutePath: string, skills: Iterable<SkillRef>): SkillRef | undefined {
  for (const skill of skills) {
    const rel = relative(skill.baseDir, absolutePath);
    if (!rel.startsWith("..") && !isAbsolute(rel)) return skill;
  }
  return undefined;
}
