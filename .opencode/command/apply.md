---
description: Activate the already-built Nix config (nh home switch)
agent: build
---

Activate the home-manager configuration in this repo by running:

```
nh home switch
```

Do **not** format or build first. `/apply` assumes the configuration has
already been built successfully (for example via `/validate`) before you run it.
A successful build is the precondition for switching, and that build has already
happened by the time `/apply` runs.

`nh` resolves the flake path and host automatically (`programs.nh.homeFlake` is
set), so do not pass a flake path or host name.

Trust the build: if `nh home switch` reports success, treat the result as
correct. Do **not** inspect, read, or dive into `/nix/store` output to
double-check the generated files — assume those outputs are correct.

**One-shot rule:** this `/apply` invocation authorises exactly one switch
attempt. If `nh home switch` fails (activation error, rollback, or any non-zero
exit):

- Stop immediately. Do **not** retry `nh home switch`.
- Report the activation error to the user and, if the cause is obvious in the
  changed `.nix` files, propose or apply a fix.
- Then wait for the user to issue a new explicit `/apply`. Never re-run
  `nh home switch` automatically after a failure, regardless of how the user
  phrases the follow-up request.
