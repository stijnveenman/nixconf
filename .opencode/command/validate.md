---
description: Format and build the appropriate Nix configuration
agent: build
---

Validate the configuration in this repo by **formatting** the Nix files and
then **building** the configuration without activating it.

1. Format all Nix files:

   ```
   alejandra .
   ```

2. Build the configuration with the command appropriate for the current host:

   - Home Manager host: `nh home build`
   - NixOS host: `nh os build`

`nh` resolves the flake path and host automatically, so do not pass a flake
path or host name.

- If the build **succeeds**, report success and stop. `/validate` does not
  activate the configuration.
- If the build **fails** (non-zero exit, Nix evaluation error, or build error),
  report the relevant error output to the user and, if the cause is obvious in
  the changed `.nix` files, propose or apply a fix and re-run the build.
  Do **not** activate a configuration that has not built successfully.
