# Architecture

```
                         ┌────────────────────────── Docker host (any) ───────────────────────────┐
 UniFi controller ──API──▶ unpoller ─────────┐                                                      │
 json-exporter ◀──API── UniFi controller ───┼──▶ Prometheus ──▶ Grafana ──alerts──▶ Telegram       │
 8.8.8.8/1.1.1.1/DNA ◀──── blackbox (ICMP) ──┤        ▲                                             │
                           node-exporter ────┘        │ textfile metrics                             │
                           (textfile only)            │                                              │
                              ▲                       │                                              │
                              └──── /data/textfile ◀── agent: probe-light.sh + watchdog.sh (1 min), probe.sh (5 min) ───ssh :2222──▶ U5G modem
                                                              (diag | cure, forced command)           (u5g-dispatch.sh)
                         └────────────────────────────────────────────────────────────────────────┘
```

## Design decisions (and why)
1. **Continuous measuring lives on the host, not on the modem.** The modem is OpenWrt on tmpfs with no boot hook:
   anything installed there (cron, rc.local, daemons) disappears on reboot. So the modem runs only short on-demand
   commands (`diag`, `cure`) and the host does all continuous probing, logging and decision making.
2. **Prometheus textfile pattern.** `probe-light.sh`/`probe.sh`/`watchdog.sh` write `.prom` files atomically (tmp + rename) into
   `data/textfile`; node-exporter (textfile collector only, host collectors disabled) exposes them.
3. **Forced-command SSH key.** The agent's key in the modem's `authorized_keys` has `command="/etc/persistent/u5g-dispatch.sh"`;
   the dispatcher allows exactly `ping`, `diag`, `radio-status` (read-only AT queries), `cure`. A stolen agent key cannot run arbitrary commands.
4. **Dedicated dropbear on port 2222.** The stock dropbear on :22 does not read `/etc/persistent/.ssh/authorized_keys`
   (OpenWrt build); a second instance started with `-D /etc/persistent/.ssh` does. It is started manually and does not survive a modem reboot.
5. **Episode definition is destination-specific.** The "bad" state is NOT a radio collapse (see FINDINGS.md): the same radio
   config gives fast and slow at different times. The reliable signature is `nopeus.dna.fi` (DNA's own server) ≪ Cloudflare.
   The detector uses DNA only: the time of a 1 MB download every minute, judged against a good-state baseline.
   (Until 2026-10-20 the 5 MB DNA + Cloudflare probe every 5 min was the detector; the 1-minute probe detects 5-12 minutes earlier and replaced it.
   The 5 MB probe stays as diagnostics: DNA vs Cloudflare, loaded RTT, OFO/DSACK, big-packet ping, public IP.)
6. **Dry-run first.** Auto-cure is gated by a mode file so the detector can be validated on real episodes before it acts.
7. **Provisioned, not clicked.** Grafana datasource (uid `prometheus`), dashboards, alert rules and the Telegram contact
   point are files; dashboards use the fixed datasource uid instead of an import-time input.

## Data flow (agent loop, period 60 s)
Every cycle: `probe-light.sh` (1 MB from DNA, judged by download time) → `/data/textfile/u5g_probe_light.prom` + `/data/state/light.log`.
Every 5th cycle: `probe.sh` (5 MB from DNA and Cloudflare, pings, TCP counters; diagnostics only) → `/data/textfile/u5g_probe.prom`.
Every cycle: the watchdog evaluates the light samples: episode = 3 in a row >= max(2 x baseline, 0.8 s), cleared after 5 in a row below
(baseline = median of ~24 h of good-state samples taken outside episodes, `/data/state/light-base.log`; non-200 samples count as neither).
On an episode, if rate limits allow and the modem answers `ping`: run `diag` (saved to
`/data/diag/episode-*.txt`) → dry: log "would cure"; live: `cure`, wait 170 s, re-run the light probe, record result → write
`/data/textfile/u5g_watchdog.prom` (see METRICS.md).
