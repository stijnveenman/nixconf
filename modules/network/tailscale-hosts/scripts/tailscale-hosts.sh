# Write every Tailscale node (self + peers) into a managed block in /etc/hosts,
# as a workaround for MagicDNS not resolving on this machine.
#
# Expects `jq` to be set by the wrapper. Writing /etc/hosts goes through
# `sudo -n /usr/bin/tee /etc/hosts`, which needs a one-time sudoers rule:
#   <user> ALL=(root) NOPASSWD: /usr/bin/tee /etc/hosts
set -euo pipefail

hosts_file=/etc/hosts
marker_begin="# BEGIN tailscale-hosts (managed by nixconf)"
marker_end="# END tailscale-hosts"

tailscale=""
for candidate in /Applications/Tailscale.app/Contents/MacOS/Tailscale "$(command -v tailscale || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    tailscale=$candidate
    break
  fi
done
if [ -z "$tailscale" ]; then
  echo "tailscale-hosts: tailscale CLI not found; leaving $hosts_file unchanged" >&2
  exit 1
fi

if ! status=$("$tailscale" status --json); then
  echo "tailscale-hosts: 'tailscale status' failed; leaving $hosts_file unchanged" >&2
  exit 1
fi

backend=$("$jq" -r '.BackendState' <<<"$status")
if [ "$backend" != "Running" ]; then
  echo "tailscale-hosts: tailscale is $backend, not Running; leaving $hosts_file unchanged" >&2
  exit 1
fi

# "<ipv4>\t<fqdn> <short>" for every node with a MagicDNS name.
entries=$("$jq" -r '
  [.Self] + ((.Peer // {}) | to_entries | map(.value))
  | .[]
  | select((.DNSName // "") != "")
  | (.DNSName | rtrimstr(".") | ascii_downcase) as $fqdn
  | ($fqdn | split(".")[0]) as $short
  | (.TailscaleIPs // [])[]
  | select(test("^[0-9.]+$"))
  | "\(.)\t\($fqdn) \($short)"
' <<<"$status" | sort -t$'\t' -k2)

current=$(cat "$hosts_file")
stripped=$(awk -v b="$marker_begin" -v e="$marker_end" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip
' "$hosts_file")

new=$(printf '%s\n%s\n' "$stripped" "$marker_begin")
if [ -n "$entries" ]; then
  new=$(printf '%s\n%s\n' "$new" "$entries")
fi
new=$(printf '%s\n%s\n' "$new" "$marker_end")

if [ "$new" = "$current" ]; then
  echo "tailscale-hosts: $hosts_file already up to date"
  exit 0
fi

printf '%s\n' "$new" | /usr/bin/sudo -n /usr/bin/tee "$hosts_file" >/dev/null
echo "tailscale-hosts: updated $hosts_file with $(printf '%s' "$entries" | grep -c . || true) entries"
