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
$SSH cure                          # starts the band cycle in the background. ONLY during an episode.
```

## Episode playbook
1. Telegram: "episode detected (dry-run)" (or "cure executed" in live mode).
2. Read `data/watchdog.log` and the newest `data/diag/episode-*.txt`. Compare with `docs/baselines/` (good-state reference): DNA vs Cloudflare speed,
   `delta ... ofo/dsack`, traceroute, `AT!GSTATUS?` cell/bands.
3. Before curing manually run extra tests worth keeping for the DNA case (the host probe history is in Prometheus already).
4. Cure (manual or auto), confirm recovery in the dashboard within ~3 min; note the cell/band change in GSTATUS.
5. Add the episode to the evidence package (screenshots with annotations, diag files).

## Tuning (`.env`, then `docker compose up -d agent`)
`WD_THRESH` (bit/s, default 8000000), `WD_NEED` (consecutive slow probes, 3), `WD_MIN_INTERVAL` (s between triggers, 10800), `WD_MAX_PER_DAY` (4).
Speedtest cadence: `SPEEDTEST_SCHEDULE` (default hourly `7 * * * *`); servers: `SPEEDTEST_SERVERS`. Probe size/target: env `SIZE`, `PINGHOST`, `DNA_URL`, `CF_URL` on the agent service.

## After a modem reboot
Alert "modem unreachable" (after 10 min) → `modem/install-modem.sh <ssh_user>@<U5G_IP>` → `ssh … ping` → alert clears. The reboot itself may have cured the episode.

## Backups
`data/` (key, mode, state, diag, logs) and the named volumes `prometheus-data`, `grafana-data`, `speedtest-config`
(`docker run --rm -v u5g_prometheus-data:/v -v $PWD:/b alpine tar czf /b/prom.tgz -C /v .`). Config is in git. Never commit `.env` or `data/`.

## Upgrades
Change image tags in `docker-compose.yml`, `docker compose pull && docker compose up -d`, then `scripts/verify.sh`. Pin `unpoller` after the first good run.
