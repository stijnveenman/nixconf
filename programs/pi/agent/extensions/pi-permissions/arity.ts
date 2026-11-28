/** How many words of a command make up its "always allow" prefix, like opencode's arity table. */
const ARITY: Record<string, number> = {
  git: 2,
  npm: 2,
  pnpm: 2,
  yarn: 2,
  bun: 2,
  npx: 2,
  bunx: 2,
  cargo: 2,
  go: 2,
  docker: 2,
  podman: 2,
  kubectl: 2,
  helm: 2,
  terraform: 2,
  gh: 3,
  nix: 2,
  "nix-env": 2,
  nh: 3,
  systemctl: 2,
  brew: 2,
  apt: 2,
  "apt-get": 2,
  pip: 2,
  uv: 2,
  poetry: 2,
  make: 2,
  just: 2,
  dotnet: 2,
  mvn: 2,
  gradle: 2,
  aws: 3,
  gcloud: 3,
  az: 3,
  acli: 4,
  td: 2,
  herdr: 3,
  wt: 2,
};

/** `git status --short` → `git status *`; stops early at an option. */
export function alwaysPattern(words: string[]): string {
  if (!words.length) return "*";
  const prefix = words.slice(0, ARITY[words[0]] ?? 1);
  const firstOption = prefix.findIndex((word, i) => i > 0 && word.startsWith("-"));
  return `${(firstOption < 0 ? prefix : prefix.slice(0, firstOption)).join(" ")} *`;
}
