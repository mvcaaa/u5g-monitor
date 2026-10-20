# Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `ssh -p 2222 … ping` → `Permission denied (publickey,password)`; dropbear log "Exit before auth … 0 fails" | You are on the wrong port, or :2222 dropbear is not running. Port 22 never reads `/etc/persistent/.ssh/authorized_keys`. Re-run `modem/install-modem.sh`; check `ps w \| grep [d]ropbear` on the modem. |
| Same, port 2222, key is offered but rejected | `authorized_keys` line garbled (long pastes get split by some terminals) - re-run the installer instead of pasting; check `wc -l` and that the key text is on one line. |
| ssh prints `denied` | That is the forced command rejecting a non-allowed command - expected for anything but `ping`, `diag`, `cure`. |
| Prometheus target `speedtest_tracker` is 403 | The scraping IP is not in Speedtest Tracker's allowed list. Add the docker network CIDR (`docker network inspect u5g_default`; the old hand-built setup needed `172.16.0.0/12`). |
| `/prometheus` returns "# no data available" | No speed test has run yet - trigger one manually. |
| Blackbox targets show 0 / probe_success 0 for some IPs | Those hosts don't answer ICMP echo (172.20.47.3 and 62.78.100.208 didn't); remove them. `funet.fi` has no A record. Image tag must be `v0.29.0` (not `0.29.0`). |
| Blackbox ICMP fails in the container | needs `cap_add: [NET_RAW]` (set in compose). |
| Grafana dashboard import error "Cannot read properties of undefined (reading 'type')" | A `row` panel with an empty `panels` array. Rows must not carry a `panels` key (the shipped JSON is fine). |
| Grafana alert in Error state | Metric not yet in Prometheus (first scrape ≤ 1 min); check `u5g_watchdog_*` in Explore. |
| Telegram `chat not found` | Wrong `TELEGRAM_CHAT_ID` or you never messaged the bot. Chat id is numeric; get it from `getUpdates`. |
| `u5g_probe_*` stale alert | `docker compose logs agent`; the agent needs internet at first start (apk). Check `data/state/heartbeat` age. |
| Agent healthcheck unhealthy | loop stuck (a cure waits ≥ 170 s, diag ≤ 220 s - give it 6 min) or `data/` not writable. |
| `probe` http_code 000 / speed 0 | host has no route to `nopeus.dna.fi:8080` or Cloudflare; the watchdog ignores non-200 samples (never counts them as slow). |
| Episode never triggers although speed is bad | needs 3 light samples in a row (HTTP 200) above `u5g_watchdog_light_threshold_seconds` (dashboard light panel); or the 3 h / 4-per-day limit is active (see `watchdog.log` "suppressed"). |
| Pasting multi-line commands garbles input (owner's terminal) | use the provided scripts/files (`scp`/`SendUserFile`), single short lines only. |
| Speedtest Tracker run fails with `Error: [-3] Try again`; the `speedtest_tracker_*` speed series vanish (only `speedtest_tracker_result_id{status="failed"}` stays) | Temporary DNS resolution failure inside the container (`EAI_AGAIN`; seen 2026-10-19 for ~20 min while ICMP and the 5 MB DNA probe were fine). Not a modem episode by itself; re-run the test. Check `getent hosts www.speedtest.net` in the container if it persists. |
| Alert fires when a speed test merely failed | The speed alert must have `noDataState: OK` (the provisioned rule has it). A hand-made rule defaulting to `NoData` pages on every failed test. Liveness is covered by "probe is stale" / "watchdog is stale". |
