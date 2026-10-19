# Operations

## Daily
- Look at the Grafana dashboard "U5G Radio Monitor (EN)": speed (Speedtest + probe), RTT/loss, Watchdog row. Alerts come to Telegram.
- Agent logs: `docker compose logs agent --tail 50` and `data/agent.log`; watchdog events: `data/watchdog.log`; per-episode diagnostics: `data/diag/episode-*.txt`.

## Mode switch (no restart)
```bash
cat data/mode            # dry | live
echo live > data/mode    # allow cure     (do this only after reviewing a dry-run episode)
echo dry  > data/mode    # back to safe
```

## Manual diagnostics / cure through the same restricted key
```bash
SSH="ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP>"
$SSH ping                          # pong
$SSH diag | tee data/diag/manual-$(date +%Y%m%d-%H%M).txt     # ~1-2 min, read-only
$SSH cure                          # starts the band cycle in the background (hold 120 s + re-registration, ~3-4 min total). ONLY during an episode.
```

## Episode playbook
1. Telegram: "episode detected (dry-run)" (or "cure executed" in live mode).
2. Read `data/watchdog.log` and the newest `data/diag/episode-*.txt`. Compare with `docs/baselines/` (good-state reference): DNA vs Cloudflare speed,
   `delta ... ofo/dsack`, traceroute, `AT!GSTATUS?` cell/bands.
3. Before curing manually run extra tests worth keeping for the DNA case (the host probe history is in Prometheus already): `ssh <ssh_user>@<U5G_IP> 'sh -s' < modem/ofo-test.sh` (admin login, read-only, ~1 min) gives speed and TCP out-of-order counters per destination (DNA / Cloudflare / DNA). Run it again after the cure for a before/after pair.
4. Cure (manual or auto), confirm recovery in the dashboard within ~3 min; note the cell/band change in GSTATUS.
5. Add the episode to the evidence package (screenshots with annotations, diag files) and record it in `docs/episodes/` (see `2026-10-19-episode-1.md` as the template).

## Tuning (`.env`, then `docker compose up -d agent`)
`WD_THRESH` (bit/s, default 8000000), `WD_NEED` (consecutive slow probes, 3), `WD_MIN_INTERVAL` (s between triggers, 10800), `WD_MAX_PER_DAY` (4).
Speedtest cadence: `SPEEDTEST_SCHEDULE` (default hourly `7 * * * *`); servers: `SPEEDTEST_SERVERS`. Probe size/target: env `SIZE`, `PINGHOST`, `DNA_URL`, `CF_URL` on the agent service.

## After a modem restart (planned reboot or firmware upgrade)
The modem runs OpenWrt from tmpfs: everything this project puts on it (dispatcher, restricted key, `band-cycle.sh`, the :2222 dropbear) lives in RAM and is **lost on every reboot**.
Nothing is written to flash by design. Expect the alert "modem unreachable" after ~10 min; the watchdog cannot diag or cure until the steps below are done.

**Before a planned restart**
1. Switch the watchdog to dry mode so it cannot start a cure while the modem is coming back: `echo dry > data/mode`.
2. Make sure the band profile is back to `00`: `ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP> diag | head -12` (shows current and defined profiles; or `AT!BAND?` as admin). Never restart while in `0D`.
3. Optional before a firmware upgrade: save a copy of `modem/band-cycle.sh` from the modem if you changed it (`ssh <ssh_user>@<U5G_IP> cat /etc/persistent/band-cycle.sh`) and run `diag` once to keep a "before" record.

**After the modem is back (wait until the radio is registered and the internet works again)**
1. Re-install the modem side: `bash modem/install-modem.sh <ssh_user>@<U5G_IP>` (re-creates the dispatcher, key line, `band-cycle.sh` if absent, and starts dropbear on :2222). Use the admin account on port 22.
2. Test the channel: `ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP> ping` → `pong`. If the host key changed after a firmware upgrade, the agent container's known_hosts is not persisted: `docker compose up -d --force-recreate agent`; for a manual test from your shell use `ssh-keygen -R '[<U5G_IP>]:2222'`.
3. Check that the custom profile survived: `ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP> diag | grep -c '^0D,'` should not be 0 (the installer also warns). Profiles are stored in the modem and normally survive a reboot, but a firmware/modem-firmware upgrade may reset them - **unverified**. If `0D` is gone and the owner wants it back: `ssh <ssh_user>@<U5G_IP> 'sh -s' < modem/create-profile-0d.sh` (see MODEM.md). Without `0D` the cure is refused, monitoring continues.
4. Check `AT!BAND?` shows `00` and `AT!SELRAT?` shows `00, Automatic`.
5. After a firmware upgrade: re-run `diag` and compare with `docs/baselines/good-state-2026-10-19.md` (idle ping ~37 ms, 4-hop traceroute, DNA 5 MB probe 28-66 Mbit/s); the AT command set, `uiwwand-chat`, `/etc/persistent` behaviour and the dropbear flags may differ in a new firmware - verify before trusting automation.
6. Only then `echo live > data/mode` (if it was live), and confirm the alert "modem unreachable" cleared and `u5g_watchdog_modem_reachable 1` is exported.
7. Note the reboot time: it may have cured an episode by itself (re-registration), which matters for the case with DNA. Mark it on the dashboard or in `watchdog.log`.

## Light probe (earlier detection)
Every minute `agent/probe-light.sh` downloads 1 MB from DNA and judges it by **time** (good state 0.3-0.8 s, calibration in `docs/baselines/light-probe-calibration-2026-10-19.md`;
slow state ~6 s or timeout). Three consecutive samples >= 2 s (HTTP 200) = a light episode, detected about 3 minutes after onset instead of ~10-15 with the 5-minute 5 MB probe.
- `cat data/light_mode`: `shadow` (default) = only logs "LIGHT episode detected [shadow]" and sets `u5g_watchdog_light_*` metrics; nothing is triggered by it.
  Compare the timestamps with the later "EPISODE:" line of the heavy probe in `data/watchdog.log` to see how much earlier it was, and watch for false detections in good periods.
- `echo primary > data/light_mode`: a light episode triggers diag (and the cure in live mode) like the heavy one, with the same interval/day limits. Do this only after the shadow run is clean.
- `echo off > data/light_mode`: ignore the light probe.
The light probe cannot see mild episodes (about 5-14 Mbit/s): 1 MB then takes < 1.6 s, like the good state. The 5-minute 5 MB probe stays as the second level.

## Backups
`data/` (key, mode, state, diag, logs) and the named volumes `prometheus-data`, `grafana-data`, `speedtest-config`
(`docker run --rm -v u5g_prometheus-data:/v -v $PWD:/b alpine tar czf /b/prom.tgz -C /v .`). Config is in git. Never commit `.env` or `data/`.

## Upgrades
Change image tags in `docker-compose.yml`, `docker compose pull && docker compose up -d`, then `scripts/verify.sh`. Pin `unpoller` after the first good run.
