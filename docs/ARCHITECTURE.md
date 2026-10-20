# Architecture

```
                         ┌────────────────────────── Docker host (any) ───────────────────────────┐
 UniFi controller ──API──▶ unpoller ─────────┐                                                      │
 Speedtest servers ◀────── speedtest-tracker ┼──▶ Prometheus ──▶ Grafana ──alerts──▶ Telegram       │
 8.8.8.8/1.1.1.1/DNA ◀──── blackbox (ICMP) ──┤        ▲                                             │
                           node-exporter ────┘        │ textfile metrics                             │
                           (textfile only)            │                                              │
                              ▲                       │                                              │
                              └──── /data/textfile ◀── agent: probe.sh (5 min) + watchdog.sh ───ssh :2222──▶ U5G modem
                                                              (diag | cure, forced command)           (u5g-dispatch.sh)
                         └────────────────────────────────────────────────────────────────────────┘
```

## Design decisions (and why)
1. **Continuous measuring lives on the host, not on the modem.** The modem is OpenWrt on tmpfs with no boot hook:
   anything installed there (cron, rc.local, daemons) disappears on reboot. So the modem runs only short on-demand
   commands (`diag`, `cure`) and the host does all continuous probing, logging and decision making.
2. **Prometheus textfile pattern.** `probe.sh`/`watchdog.sh` write `.prom` files atomically (tmp + rename) into
   `data/textfile`; node-exporter (textfile collector only, host collectors disabled) exposes them.
3. **Forced-command SSH key.** The agent's key in the modem's `authorized_keys` has `command="/etc/persistent/u5g-dispatch.sh"`;
   the dispatcher allows exactly `ping`, `diag`, `cure`. A stolen agent key cannot run arbitrary commands.
4. **Dedicated dropbear on port 2222.** The stock dropbear on :22 does not read `/etc/persistent/.ssh/authorized_keys`
   (OpenWrt build); a second instance started with `-D /etc/persistent/.ssh` does. It is started manually and does not survive a modem reboot.
5. **Episode definition is destination-specific.** The "bad" state is NOT a radio collapse (see FINDINGS.md): the same radio
   config gives fast and slow at different times. The reliable signature is `nopeus.dna.fi` (DNA's own server) ≪ Cloudflare.
   The detector uses DNA only (< 8 Mbit/s, 3 probes in a row, HTTP 200 required).
6. **Dry-run first.** Auto-cure is gated by a mode file so the detector can be validated on real episodes before it acts.
7. **Provisioned, not clicked.** Grafana datasource (uid `prometheus`), dashboards, alert rules and the Telegram contact
   point are files; dashboards use the fixed datasource uid instead of an import-time input.

## Data flow (agent loop, period 60 s)
Every cycle: `probe-light.sh` (1 MB from DNA, judged by download time) → `/data/textfile/u5g_probe_light.prom` + `/data/state/light.log`.
Every 5th cycle: `probe.sh` (5 MB from DNA and Cloudflare, pings, TCP counters) → `/data/textfile/u5g_probe.prom`.
Every cycle: the watchdog appends a heavy sample to `/data/state/history.log` when a new one exists and evaluates both detectors:
heavy = last 3 samples < 8 Mbit/s; light = 3 light samples in a row >= max(4 x baseline, 1.5 s), cleared after 5 in a row below (baseline = median of ~24 h of good-state samples, `/data/state/light-base.log`; non-200 samples count as neither). The light detector only logs/counts in `shadow` mode (`/data/light_mode`)
and triggers like the heavy one in `primary` mode. On an episode, if rate limits allow and the modem answers `ping`: run `diag` (saved to
`/data/diag/episode-*.txt`) → dry: log "would cure"; live: `cure`, wait 170 s, re-probe, record result → write
`/data/textfile/u5g_watchdog.prom` (see METRICS.md).
