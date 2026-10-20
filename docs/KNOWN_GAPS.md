# Known gaps and unverified items (read before trusting the repo blindly)

## Not captured from the live system (could not be read from the authoring environment)
1. **unpoller settings** are reconstructed from the project summary (API-key auth, Prometheus on :9130, InfluxDB disabled). Tag is `latest`; pin it.
2. The **"Speed drop" alert** (< 20 Mbit/s, `for 10m`) was created by hand in the live Grafana; its provisioned twin here (`u5g-speed-drop`) is rebuilt from that description.

## json_exporter in the compose stack
`config/json_exporter/json_exporter.yml` equals the live TrueNAS config byte for byte once the key is filled in. The compose services `json-exporter` and
`prometheus`, run against a stub controller serving a captured `stat/device` response, produced the same 10 `u5g_*` series as the live exporter.
Not run: the compose `json-exporter` against the real controller (TLS, API key accepted).

## Light probe calibration
The baseline threshold (`LIGHT_K=2`, `LIGHT_FLOOR_SEC=0.8`, clear after 5) was chosen from ~19 h of history with two severe episodes (2026-10-20): they are 3.5-5 s against a baseline of ~0.47 s, and in ~9 h of good state no threshold of 0.8 s or more was exceeded 3 times in a row. Detection of mild drops (~10 Mbit/s) is an estimate; no mild episode is in the data yet. That is a small sample; the shadow mode stays until more episodes and good days confirm it. A baseline learned during a long episode is excluded by design (only fast samples outside light episodes are learned), but an episode that starts before 30 baseline samples exist is judged against the 0.5 s default.

## Episode tests
`agent/episode-tests.sh` ran on TrueNAS (layout B) in the good state and in the Alpine agent image (downloads only; Docker Desktop fakes ICMP); the watchdog
hook was tested with stubs (dry, live, `EPTEST=off`, default path). It has **not yet run during a real episode**. Under a 1.5 Mbit/s episode each download
takes ~27 s, so the whole run should take ~3.5 min - an estimate.

## Timing caveats
- A cure takes >= 120 s (the hold in `band-cycle.sh`) plus re-registration on `00`, but the watchdog re-measures **170 s** after sending it (`WAITAFTER`): only ~50 s after `00` is set.
  A "cure did not help" result right after a cure may be a false negative - check the dashboard a few minutes later before concluding. Not changed yet (owner decision: keep waiting times as they are). Data point from episode 1: the first good probe came 90 s after `00` was restored (the re-measure at 170 s would have run ~49 s after `00` - untested whether that is already enough).
- Whether a shorter hold (< 120 s) also cures is untested.

## Never executed end-to-end in the authoring environment (no Docker daemon there)
- `docker compose up`, image pulls (tags `prom/prometheus:v3.5.0`, `grafana/grafana:12.1.0`, `prom/node-exporter:v1.9.1` are unverified - `docker compose pull` fails loudly if one is wrong; `blackbox-exporter:v0.29.0` was used live),
  Grafana file provisioning of alert rules/contact point (live rules were created through the HTTP API, and the equivalent payloads worked).
- Validated only: YAML/JSON syntax, `docker compose config`, shell syntax, `init.sh` (with a stubbed `ssh-keygen`), watchdog decision logic with stubbed ssh/probe (dry and live paths) and replayed light-probe history, `setup`-time scripts earlier run live on TrueNAS (probe v3, watchdog, dispatcher, forced-command key).
- `scripts/verify.sh` has never been run against a real stack.

## Design limitations
- Modem reboot wipes the dispatcher/key/:2222 listener (MODEM.md). Alert "modem unreachable" is the mitigation.
- Auto-cure (live mode, on since 2026-10-20 21:00) has only been exercised with stubs; the first real automatic cure is still to come. Manual cures with the same `band-cycle.sh` worked in episodes 1, 3 and 4.
- The detector sees only DNA's server and only the time of 1 MB. The 5 MB diagnostic probe (DNA vs Cloudflare, loaded RTT, OFO) is noisy (e.g. DNA 28 vs 66 Mbit/s a few minutes apart in the good state) and no longer decides anything.
