# Pi configuration

`modules/pi.nix` links the hand-maintained parts of Pi's global configuration
from `pi/agent` into `~/.pi/agent`. Pi's mutable state remains outside the
repository: authentication, sessions, model cache, and its npm environment are
not configuration and should not be committed.

Edit these files directly and Pi will see the changes immediately; an `nh`
switch is only needed when changing the Home Manager links themselves.

## Remote extensions

The `packages` entry in `agent/settings.json` is Pi's built-in package mechanism.
It currently installs `npm:@narumitw/pi-btw`. This is the lowest-friction option
for public extensions: prefer an exact version (or a lockfile in Pi's npm state)
and periodically update it deliberately.

Other options, from least to most reproducible:

1. **Pi npm packages** — keep the package name/version in `settings.json`; let
   Pi maintain its npm installation. Good for small public extensions.
2. **A separate extension repository** — publish it as an npm package and pin a
   release. This avoids submodules while keeping the extension independently
   versioned.
3. **A flake input** — add the extension repository as a flake input and expose
   its files through a Nix module. This gives reproducible source revisions but
   requires an `nh` build/switch to update and is less suitable for live editing.
4. **`git subtree`** — vendor a remote repository into `pi/agent/extensions`.
   It avoids submodule UX and keeps one checkout, but updates are explicit
   subtree pulls and the vendored code becomes part of this repository.

For this setup I would use npm packages for stable public extensions, local
symlinked TypeScript for extensions under active development, and a separate
repo (or subtree) only for extensions that need source review or local patches.
Do not put Pi auth, sessions, or npm credentials in this repository.
