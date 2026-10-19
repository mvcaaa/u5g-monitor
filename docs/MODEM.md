# The U5G modem (UniFi 5G Max Outdoor) - facts needed to operate it

- Hardware/OS: Sierra Wireless **EM9291** modem inside a UniFi device running **OpenWrt 25.12.2**.
- The admin SSH user on the modem is **uid 0** (root-equivalent), home `/etc/persistent`, shell ash. Its name is configurable (`U5G_SSH_USER`).
- **Filesystem:** `/` is tmpfs → everything outside the persistent areas vanishes on reboot, including `/etc` changes, cron, rc.local.
  There is **no autostart hook** (searched `/usr/etc/rc.d/*`, preinit scripts: nothing user-extensible).
  `/etc/persistent` is restored from flash (via `cfgmtd`) at boot - but only what was saved to flash. `/tmp/log` is a persistent ext4 partition.
- Two dropbear instances: stock on :22 (`/usr/sbin/dropbear -F -r ... -p 22`) which does **not** read `/etc/persistent/.ssh/authorized_keys`
  (on this build root keys come from `/etc/dropbear/authorized_keys`, empty/tmpfs), and a manually started one on :2222:
  `dropbear -r /var/run/dropbear_ed25519_host_key -p 2222 -l br0 -D /etc/persistent/.ssh -E`.
  Dropbear 2025.89 honours `command=`, `no-pty`, `no-port-forwarding`, `no-agent-forwarding`; **`restrict` was not the problem, the port was**.
  Dropbear logs auth failures only at info level without reasons (`logread | grep dropbear`).
- BusyBox userland: `ping` has no DF flag (`-M do` unsupported), so big-packet DF tests are done from the host, not the modem.
  Available: `curl`, `traceroute`, `awk`. `socat` is not present.

## What the repo installs on the modem (RAM-overlay of /etc/persistent, NOT flash)
| File | Role |
|---|---|
| `/etc/persistent/u5g-dispatch.sh` | forced command: `ping` → pong, `diag` → diagnostic bundle (~1-2 min), `cure` → `nohup sh band-cycle.sh &`, anything else → `denied` |
| `/etc/persistent/band-cycle.sh` | the cure (see below) |
| line in `/etc/persistent/.ssh/authorized_keys` | `command="/etc/persistent/u5g-dispatch.sh",no-pty,no-port-forwarding,no-agent-forwarding ssh-ed25519 AAAA… u5g-watchdog` |
| dropbear on :2222 | key auth for the above |
**After a modem reboot all of this is gone** (the `authorized_keys` line may survive if flash already had it, the rest does not). Effect: `modem_reachable=0`,
Grafana alert "modem unreachable", auto-cure blocked. Fix: re-run `modem/install-modem.sh`. A modem reboot is itself a cure for an episode.

### Optional: making it survive reboots (NOT done; needs the owner's explicit approval, flash writes carry risk)
Mechanism found in `/usr/bin/syswrapper.sh`: `touch /var/run/need_cfg_save; /usr/bin/syswrapper.sh cfg_save_check` saves `/etc/persistent` to flash;
verify with `cfgmtd -r -p /tmp/run -f /tmp/run/read.cfg`. Even then nothing *starts* dropbear:2222 at boot (no hook), so the :2222 listener would still need
re-starting - an unsolved gap; the realistic design is "re-run install-modem.sh after a modem reboot".

## The cure
`AT!BAND=0D` then `AT!BAND=00` through `uiwwand-chat -t N '<AT cmd>'`. Profile `00` = all bands; `0D` = "No n28 Test" (same masks, NR NSA without n28).
The modem re-registers in ~2 minutes; internet is essentially uninterrupted (the user verified no real outage). Typical visible effect: serving cell
cell A → cell B, LTE B3 → B1+B3, NR ARFCN 152600 → 156600, and speed 5 → ~200 Mbit/s. Other profiles: 01, 02, 06-09, 0C (standard sets).
`band-cycle.sh` in this repo is a reconstruction (20 s between the two commands); the live original was 634 bytes (KNOWN_GAPS.md).
Lighter alternatives were **not** tested: `AT+CGATT=0` / `=1` (supported), `AT+COPS`, `AT+CFUN`. Candidate experiment for a dry-run episode.

## Useful AT commands (read-only unless marked)
`AT!BAND?` current profile · `AT!BAND=?` profiles · `AT!GSTATUS?` radio status (cell id, bands, RSRP/SINR, NR5G block) · `AT!NRINFO?` ·
`AT+CGATT?`. Writes: `AT!BAND=xx` (cure), `AT+CGATT=0/1`, `AT+CFUN=…` (disruptive). The Sierra EM9 AT reference is gated; effects of write commands beyond `AT!BAND` are unverified.
