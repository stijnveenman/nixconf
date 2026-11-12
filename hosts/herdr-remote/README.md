# herdr-remote

An x86-64 NixOS VM for Herdr, Pi, Claude Code, Git, Worktrunk and Neovim.
The VM runs Tailscale as a NixOS service; enrollment and Tailscale SSH setup
are manual. There is no image publishing or automatic deployment.

## Before installing

- Create an x86-64 Unraid VM with **UEFI/OVMF** firmware, a network connection,
  and a dedicated virtual disk. The configuration uses DHCP and QEMU virtio
  drivers. Give the installer sufficient memory and storage to build the system
  remotely if you do not have an x86-64 Linux builder.
- Boot an SSH-accessible Linux or NixOS installer in the VM. `nixos-anywhere`
  needs root SSH access or passwordless sudo on the installer, and the installer
  must remain reachable after kexec. A connection that only works through
  Tailscale on the original OS will not survive a standard kexec installer.
- The configured installation disk is `/dev/vda`. Before installation, confirm
  with `lsblk` that it is the **VM's own virtual disk**, and update `disk.nix`
  if necessary. **nixos-anywhere and disko erase the selected disk**, including
  any existing data.
- `configuration.nix` authorizes the Mac's existing `~/.ssh/id_ed25519.pub`
  public key for root and `herdr-remote` as installation/recovery access. Verify
  that you can use its private key from the machine running the installer, or
  replace the public key before installing. This key is separate from the Git
  key you will create inside the VM.

## Install manually

From the nixconf checkout, after confirming the disk and SSH access:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --build-on remote --flake .#herdr-remote --target-host root@<VM-IP>
```

This builds on the target rather than requiring an x86-64 Linux builder on the
Mac. It partitions the disk, installs NixOS and reboots the VM. Verify the new
SSH host key out of band after installation; it will differ from the installer
unless you deliberately preserve the old key.

The installed VM accepts key-only OpenSSH connections on its network interfaces
for bootstrap and recovery. No password is configured for the normal user; use
root SSH with the authorized key for administration.

## Connect and configure

1. Connect as root over the VM's LAN address and run `tailscale up --ssh`. Follow
   the login URL and approve the device. Configure your tailnet's network and
   SSH policy to allow the `herdr-remote` Linux user.
2. From your Mac, verify `ssh herdr-remote@<tailscale-ip>`, then run
   `herdr --remote herdr-remote@<tailscale-ip>`. Always use the VM's Tailscale
   IP (see `tailscale ip -4` on the VM or the Tailscale admin console); the
   `herdr-remote` hostname is not set up to resolve, so don't rely on it.
3. Create your Git SSH key and configure your Git identity inside the VM. Log in
   to Pi and Claude Code using their normal authentication flows. Place or mount
   repositories wherever you prefer; no repository mount is configured here.

Tailscale SSH is available only after enrollment and subject to tailnet policy.
The independent key-only OpenSSH service remains enabled for recovery.

## Persistence and later updates

The VM disk contains `/home/herdr-remote` (including agent credentials,
sessions, worktrees and SSH keys) and `/var/lib/tailscale` (Tailscale identity).
Normal NixOS rebuilds preserve them. Back up the VM disk and protect its backups;
re-running the installer with the disko phase will erase it.

For normal updates, use `nh`, not NixOS Anywhere. On the VM, from its nixconf
checkout:

```sh
alejandra .
nh os build .
# Only after the build succeeds:
nh os switch .
```

From the Mac, use the VM as both the Linux builder and target. Replace the host
with its actual Tailscale name or address and use an SSH account authorized to
administer the VM:

```sh
alejandra .
nh os build . -H herdr-remote --build-host root@herdr-remote --target-host root@herdr-remote
# Only after the build succeeds:
nh os switch . -H herdr-remote --build-host root@herdr-remote --target-host root@herdr-remote
```

Build and switch the same worktree. Follow the build, switch and failure rules
in the root `AGENTS.md`; ask permission before remote operations. NixOS Anywhere
is for provisioning, and its default install flow erases the configured disk;
ask permission before using it, including for remote builds. There is no
automatic update or deployment. Agent processes do not survive a VM restart,
although Herdr can restore layouts and resume supported agent sessions.
