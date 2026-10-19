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

## The cure and the custom profile `0D`
**`0D` is a CUSTOM profile created by the owner; it does not exist on a stock modem.** Name `No n28 Test`. Its masks (from `AT!BAND=?`,
full table in [baselines/band-profiles.txt](baselines/band-profiles.txt)) equal profile `00` ("All bands") in GW, LTE and NRSA, and differ only in the
NR NSA mask, where n28 is cleared (bit `0x0000000008000000`):
```
00  3 - NRNSA: 000081A03B0A38D7 0000000000007C62
0D  3 - NRNSA: 000081A0330A38D7 0000000000007C62
```
Stock profiles: 00 (All bands), 01, 02, 06-09, 0C. Active selection `AT!SELRAT?` = `00, Automatic` (the vendor warns that `!BAND` and `!SELRAT` used together can
conflict; leave SELRAT on Automatic).

### How `0D` was created (verified from the owner's shell history on the modem, 2026-10-19)
One command per RAT, no password needed through `uiwwand-chat`. Syntax from the Sierra EM9 AT reference
(`AT!BAND=<Index>,<Operation>,"<Name>",<RAT>,<masks>`; Operation 1 = add, 0 = delete; RAT 0 GSM/WCDMA, 1 LTE, 3 NR NSA, 4 NR SA; index range 0-13 hex):
```
uiwwand-chat -t 5 'AT!BAND=0D,1,"No n28 Test",1,0000A7E2BB0F38DF,0000000000000042'
uiwwand-chat -t 5 'AT!BAND=0D,1,"No n28 Test",3,000081A0330A38D7,0000000000007C62'
uiwwand-chat -t 5 'AT!BAND=0D,1,"No n28 Test",0,100200000EC00000'
uiwwand-chat -t 5 'AT!BAND=0D,1,"No n28 Test",4,000081A03B0A38D7,0000000000007C62'
```
`modem/create-profile-0d.sh` runs exactly these, **refuses to overwrite an existing 0D**, and verifies the result against the expected masks. It writes to the modem's
profile table (it never changes the active profile), so it is run by hand by the owner, never by automation: `ssh <ssh_user>@<modem_ip> 'sh -s' < modem/create-profile-0d.sh`.
Deleting a profile would be `AT!BAND=0D,0` per the reference - not used and not tested.

### The cure (`band-cycle.sh`)
`AT!BAND=0D`, hold, then `AT!BAND=00` (via the EXIT trap). **Default hold = 120 s** (`sh band-cycle.sh [wait_sec]`), so one cycle takes >= 2 minutes plus re-registration time on `00`.
This is the owner's live script (captured 2026-10-19) plus one addition: it aborts with exit 3 and changes nothing if `AT!BAND=?` does not list `0D`.
It logs to `/tmp/band-cycle.log` (tmpfs, lost on reboot). HUP/INT/TERM end the script and the EXIT trap restores `00`, but the shell runs the trap only after the current `sleep`
finishes (up to `wait_sec`); SIGKILL cannot be handled - after any manual interruption check that `AT!BAND?` shows `00`. Never leave the modem in `0D` (it silently lacks n28 NSA).
The dispatcher's `cure` refuses (exit 3) when `0D` is missing; `install-modem.sh` warns; `diag` prints the defined and current profiles.
Effect: typical visible change is serving cell A → cell B, LTE B3 → B1+B3, NR ARFCN 152600 → 156600, speed 5 → ~200 Mbit/s; internet is essentially uninterrupted (no real outage).
Shorter holds (e.g. `wait_sec` 20) are **untested**; a possible experiment during an episode (fall back to the default hold if the speed does not recover).
Lighter alternatives were **not** tested: `AT+CGATT=0` / `=1` (supported), `AT+COPS`, `AT+CFUN`.

## Useful AT commands (read-only unless marked)
`AT!BAND?` current profile · `AT!BAND=?` profiles · `AT!GSTATUS?` radio status (cell id, bands, RSRP/SINR, NR5G block) · `AT!NRINFO?` ·
`AT+CGATT?`. Writes: `AT!BAND=xx` (cure), `AT+CGATT=0/1`, `AT+CFUN=…` (disruptive). The Sierra EM9 AT reference is gated; effects of write commands beyond `AT!BAND` are unverified.
