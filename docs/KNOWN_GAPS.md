# Known gaps and unverified items (read before trusting the repo blindly)

## Not captured from the live system (could not be read from the authoring environment)
1. **json_exporter job `u5g_ca`** (carrier-aggregation data from the UniFi API via JSONPath → `u5g_ca_lte_present{primary,band}` etc.).
   Its config contained an API key and was never copied here. Consequence: dashboard panel 106 ("carriers", both dashboards) shows no data,
   and the commented job in `config/prometheus/prometheus.yml` is a placeholder. Rebuild from the UniFi controller's device API if the panel is wanted.
3. **unpoller settings** are reconstructed from the project summary (API-key auth, Prometheus on :9130, InfluxDB disabled). Tag is `latest`; pin it.
4. The **"Speed drop" alert** (< 20 Mbit/s, `for 10m`) was created by hand in the live Grafana; its provisioned twin here (`u5g-speed-drop`) is rebuilt from that description.
5. Russian dashboard: row/panel titles still say "каждые 7 мин" - wrong, Speedtest Tracker runs **hourly** (`7 * * * *`).

## Timing caveats
- A cure takes >= 120 s (the hold in `band-cycle.sh`) plus re-registration on `00`, but the watchdog re-measures **170 s** after sending it (`WAITAFTER`): only ~50 s after `00` is set.
  A "cure did not help" result right after a cure may be a false negative - check the dashboard a few minutes later before concluding. Not changed yet (owner decision: keep waiting times as they are).
- Whether a shorter hold (< 120 s) also cures is untested.

## Never executed end-to-end in the authoring environment (no Docker daemon there)
- `docker compose up`, image pulls (tags `prom/prometheus:v3.5.0`, `grafana/grafana:12.1.0`, `prom/node-exporter:v1.9.1` are unverified - `docker compose pull` fails loudly if one is wrong; `blackbox-exporter:v0.29.0` was used live),
  Grafana file provisioning of alert rules/contact point (live rules were created through the HTTP API, and the equivalent payloads worked), Speedtest Tracker env-based Prometheus integration (live: enabled in the UI).
- Validated only: YAML/JSON syntax, `docker compose config`, shell syntax, `init.sh` (with a stubbed `ssh-keygen`), watchdog decision logic with stubbed ssh/probe (dry and live paths), `probe.sh` offline smoke test, `setup`-time scripts earlier run live on TrueNAS (probe v3, watchdog, dispatcher, forced-command key).
- `scripts/verify.sh` has never been run against a real stack.

## Design limitations
- Modem reboot wipes the dispatcher/key/:2222 listener (MODEM.md). Alert "modem unreachable" is the mitigation.
- Auto-cure has only been exercised in tests; the first real `live` cure is an open experiment. Keep dry-run until an episode has been observed.
- Probe size is 5 MB single stream: noisy (e.g. DNA 28 vs 66 Mbit/s a few minutes apart in the good state). The 3-in-a-row rule and 8 Mbit/s threshold are meant to absorb this.
