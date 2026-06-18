---
description: Validate the Nix home-manager config (nh home build)
agent: build
---

Validate the home-manager configuration in this repo by **formatting** the Nix
files and then **building** the configuration without activating it.

1. Format all Nix files:

   ```
   alejandra .
   ```

2. Build the configuration:

   ```
   nh home build
   ```

`nh` resolves the flake path and host automatically (`programs.nh.homeFlake` is
set), so do not pass a flake path or host name.

- If the build **succeeds**, report success and stop. Do **not** run
  `nh home switch`.
- If the build **fails** (non-zero exit, Nix evaluation error, or build error),
  report the relevant error output to the user and, if the cause is obvious in
  the changed `.nix` files, propose or apply a fix and re-run `nh home build`.
  Do **not** activate a configuration that has not built successfully.
