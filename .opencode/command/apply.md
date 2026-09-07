---
description: Activate the already-built Nix configuration
agent: build
---

Activate the already-built configuration with the command appropriate for the
current host:

- Home Manager host: `nh home switch`
- NixOS host: `nh os switch`

Do **not** format or build first. `/apply` assumes the configuration has
already been built successfully (for example via `/validate`) before you run it.
A successful build is the precondition for switching, and that build has already
happened by the time `/apply` runs.

`nh` resolves the flake path and host automatically, so do not pass a flake
path or host name.

Trust the switch: if it reports success, treat the result as correct. Do **not**
inspect, read, or dive into `/nix/store` output to double-check the generated
files.

If the switch fails for any reason, including a conflict with an existing file:

- Stop immediately and report the activation error.
- Do not retry the switch.
- Do not run other commands, modify or remove files, or add force flags in an
  attempt to make activation succeed.
