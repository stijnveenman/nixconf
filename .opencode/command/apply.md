---
description: Build then activate the Nix config (nh home build, then nh home switch)
agent: build
---

Build and then activate the home-manager configuration in this repo, gating the
activation on a successful build.

1. First format and validate by building:

   ```
   alejandra .
   nh home build
   ```

2. **Only if the build succeeds**, activate the configuration:

   ```
   nh home switch
   ```

`nh` resolves the flake path and host automatically (`programs.nh.homeFlake` is
set), so do not pass a flake path or host name.

If the build in step 1 **fails** (non-zero exit, Nix evaluation error, or build
error):

- Stop. Do **not** run `nh home switch`.
- Report the relevant error output to the user and, if the cause is obvious in
  the changed `.nix` files, propose or apply a fix and re-run `nh home build`
  before switching.
