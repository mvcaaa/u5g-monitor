# AGENTS.md - instructions for automated agents working in this repository

You are expected to deploy, operate or modify this stack **without prior context**. Read this file fully, then follow the reading order in
[README.md](README.md#documentation-reading-order). If anything here conflicts with a request, the safety rules below win unless the owner says otherwise explicitly.

## What this is (30 seconds)
A Docker Compose stack that monitors a UniFi 5G Max Outdoor (U5G) modem on a Finnish mobile network, detects "slow episodes" (download speed to the
operator's own server collapses from ~60-200 to ~1-14 Mbit/s while radio KPIs look fine), collects diagnostics, and can **cure** an episode by cycling the
modem's band profile through a restricted SSH key. Components: Prometheus, Grafana (provisioned), blackbox, node-exporter (textfile only), unpoller, json-exporter (carrier aggregation),
and an `agent` container (`agent/probe-light.sh` and `agent/watchdog.sh` every minute, the diagnostic `agent/probe.sh` every 5 min, `agent/episode-tests.sh` once per triggered episode).

## Safety rules (non-negotiable)
1. **Never set `data/mode` to `live`** and never run `cure` unless the owner explicitly approved it in the current conversation. Default and fallback is `dry`.
2. **Never run `cure` (or `AT!BAND=…`) outside a confirmed slow episode.** It briefly re-registers the modem; healthy-state runs only add risk.
3. **Band profile `0D` is custom:** never delete, redefine or overwrite band profiles, never run `AT!BAND=…` other than the cure's `0D`/`00`, and after any manual experiment make sure
   `AT!BAND?` shows `00`. If `diag` shows no `0D`, report it. `modem/create-profile-0d.sh` (verified syntax, refuses to overwrite) may be run **only on the owner's explicit request**.
4. **Never write the modem's flash** (`cfg_save_check`, `cfgmtd -w`, firmware tools) and never overwrite an existing `/etc/persistent/band-cycle.sh` on the modem.
   `modem/install-modem.sh` is the only sanctioned way to touch the modem; it writes to the RAM overlay only.
5. **Secrets never enter chat, logs, commits or issues:** `.env` (Telegram token, UniFi API key, Grafana password), `data/id_u5g` (watchdog private key). Do not echo them, do not `cat .env`, redact when quoting config. Both `.env` and `data/` are git-ignored - keep it that way.
6. **No destructive operations without approval:** `docker compose down -v`, deleting volumes, `rm -rf data/`, `git push --force`, deleting Grafana rules/dashboards.
7. The agent's modem key is restricted to `ping | diag | radio-status | cure` by a forced command (`radio-status` added 2026-10-21 on the owner's decision). Do not widen it further without the owner, do not add other keys, do not enable password-less root elsewhere.
8. Do not add active measurements that push large traffic: the unlimited plan is capped; probes are a 1 MB light probe per minute plus the diagnostic 5 MB per target (DNA, Cloudflare) per 5 min by design (about 4.3 GB/day together), plus ~21 MB of episode tests per trigger (at most one per hour) and two good-state reference runs a day (~42 MB/day). Do not add more or raise sizes/rates without the owner's approval.
9. Report honestly. If a check was not run, say so; do not describe the stack as "working" from syntax checks alone (see docs/KNOWN_GAPS.md for what was never run end to end).
10. The light probe is the only episode detector (since 2026-10-20, owner's decision); in `dry` mode it triggers `diag` only. Do not loosen its threshold (`LIGHT_K`, `LIGHT_FLOOR_SEC`) without replaying history for false detections (docs/OPERATIONS.md "Light probe"); the out-of-order fast rule (`LIGHT_OOO` > 0, with `LIGHT_OOO_SEC`) is enabled only by the owner.

## Repository map and invariants
| Area | Invariant |
|---|---|
| `agent/probe-light.sh` | writes `data/textfile/u5g_probe_light.prom` **atomically** (tmp + `mv`) and appends to `data/state/light.log`; metric names are an interface used by dashboards and alerts (docs/METRICS.md) - do not rename without updating `config/` |
| `agent/probe.sh` | diagnostics only (5 MB DNA + Cloudflare, loaded RTT, OFO/DSACK, 1472 B ping, public IP); writes `data/textfile/u5g_probe.prom` atomically; not used for detection |
| `agent/watchdog.sh` | episode starts after `LNEED` (3) light samples in a row (HTTP 200) >= max(`LK` (2) x baseline, `LFLOOR` (0.8 s)) and ends after `LOUT` (5) below; baseline = median of ~24 h of good-state samples (`state/light-base.log`); non-200 samples count as neither; also starts at once on ONE sample >= `LOOOT` (3 s) with >= `LOOO` (100) out-of-order packets; no cure unless the diag shows DNA < `CONFMB` (10) Mbit/s and Cloudflare >= `CONFRATIO` (5) x faster or >= `CONFOFO` (0.2) of segments out of order (otherwise the trigger is "not confirmed": no alert, no `MININT`, re-checked after `RECHECK`/`RECHECKF`); episode tests off (`EPTEST`); limits: `MININT` 1 h between triggers, `MAXDAY` 0 = no daily limit |
| `agent/episode-tests.sh` | run by the watchdog once per trigger, after `diag` and before a cure; ~21 MB; also a good-state reference twice a day (`EPT_KIND=reference`); writes `data/textfile/u5g_eptest_<kind>.prom` atomically and a `.pcap` of the downloads; needs `python3`, iputils `ping`, `tcpdump` (in the agent image) |
| `agent/radio-status.sh` | every 5 min: dispatcher `radio-status` (GSTATUS, LTEINFO, NRINFO; no traffic) -> raw `data/radio/<date>.txt` + `data/textfile/u5g_radio.prom` |
| `modem/u5g-dispatch.sh` | the forced command; allowed commands exactly `ping`, `diag`, `radio-status`, `cure`, everything else `denied`. Runs under BusyBox ash on OpenWrt - no bashisms, no `ping -M` |
| `config/grafana/` | datasource uid is `prometheus` (dashboards reference it directly); dashboards: `row` panels must NOT contain a `panels` key (import fails); keep dashboard `uid`s stable |
| `config/prometheus/prometheus.yml` | contains the placeholder `__U5G_IP__`; the rendered file is generated by `scripts/init.sh` and git-ignored |
| `Dockerfile`, `agent/crontab`, `agent/init.sh` | the agent image (`ghcr.io/mvcaaa/u5g-agent`, built by `.github/workflows/agent-image.yml` on push to `main`): pinned Alpine digest and supercronic checksum; the schedule lives only in `agent/crontab` (the watchdog runs right after the light probe); deployments pin the image by digest. Publishing the image (push) is the owner's action |
| TrueNAS host | **nothing of the project on the TrueNAS OS** (owner, 2026-10-29): no cron jobs, no scripts, no packages; only the agent's data directory as a volume. Custom App template: `deploy/truenas-agent-app.yml` |
| `docker-compose.yml` | no `build:` sections (must stay usable as a TrueNAS Custom App); service names are used as hostnames in Prometheus config |

## Playbooks
- **Deploy:** follow [docs/DEPLOY.md](docs/DEPLOY.md) exactly; success = `bash scripts/verify.sh` exits 0, Telegram test received, `data/mode` = `dry`. On TrueNAS see docs/TRUENAS.md.
- **An episode happened:** read `data/watchdog.log` and the newest `data/diag/episode-*.txt`, compare with `docs/baselines/`, summarise differences (DNA vs Cloudflare speed, OFO/DSACK deltas, traceroute, cell/bands from GSTATUS). Propose, do not execute, a cure unless approved.
- **Change thresholds:** edit `.env` (`LIGHT_*`, `WD_*`), `docker compose up -d agent`. Explain the trade-off (sensitivity vs false positives: the good state's 1 MB time has a tail up to ~1.1 s).
- **Add a probe target:** add a probe script writing its own `.prom` file, update `docs/METRICS.md` and dashboard panels and, if it should count for episodes, the watchdog logic - then test with stubs (below).
- **Look at live metrics/alerts:** if a read-only Grafana MCP is configured (docs/MCP.md), use it (`query_prometheus`, `alerting_rules_read`) instead of guessing; it cannot and must not be used to change anything.
- **Edit a dashboard:** modify JSON under `config/grafana/dashboards/`, keep `${DS}`-style inputs out (use datasource uid `prometheus`), validate JSON. There is one dashboard, `u5g-radio-monitor-en.json` (English only).
- **Modem rebooted / `modem unreachable` alert:** `bash modem/install-modem.sh <ssh_user>@<U5G_IP>`, then `ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP> ping` must print `pong`. Planned restart or firmware upgrade: follow docs/OPERATIONS.md "After a modem restart" (watchdog to `dry` first, profile back to `00`, check that `0D` survived, re-install the modem side, compare `diag` with the baselines).

## Before you commit (all must pass)
```bash
for f in agent/*.sh modem/*.sh scripts/*.sh; do bash -n "$f" || echo "BAD $f"; done        # shell syntax
python3 -c "import json,glob;[json.load(open(f)) for f in glob.glob('config/grafana/dashboards/*.json')]"   # dashboards parse
python3 -c "import yaml,glob;[yaml.safe_load(open(f)) for f in glob.glob('config/**/*.yml',recursive=True)+['docker-compose.yml']]"
cp .env.example .env && sed -i 's/^U5G_IP=.*/U5G_IP=192.0.2.10/' .env   # documentation address; fill other required vars with dummies
bash scripts/init.sh && docker compose config --quiet                                          # compose + bootstrap (needs ssh-keygen or docker)
```
Then test watchdog logic with stubs: set `D` to a temp dir, `SSHC` to a stub that answers `ping`/`diag`/`cure`, `PROBE` to a stub that appends a light sample, seed
`state/light.log` with slow samples (`<ts> <seconds> 200 1000000`), run `bash agent/watchdog.sh` in `dry` and `live` and check `watchdog.log` and `textfile/u5g_watchdog.prom`.
Finally `git status` must not show `.env`, `data/*` (except `.gitkeep`) or the rendered Prometheus config, and a grep for secrets/personal identifiers must be empty.

## Conventions
- Docs and code comments in English; `README.ru.md` is the short Russian version - update it when README changes meaningfully.
- Shell: `bash` for host/container scripts, plain POSIX `sh` for anything that runs on the modem. Scripts must not depend on the executable bit (call them with `bash`).
- Prefer delivering changes as files/patches and short single-line commands; very long or multi-line pasted commands are error-prone in some terminals.
- Keep `docs/KNOWN_GAPS.md` honest: add what you could not verify, remove items only after verifying them.
- Commit messages: imperative subject, wrap body at ~72 columns; one logical change per commit.
