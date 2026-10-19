# u5g-monitor

Monitoring, diagnostics and **automatic recovery** for a roof-mounted **UniFi 5G Max Outdoor (U5G)** on DNA Finland,
whose download speed periodically collapses from ~200 Mbit/s to ~5-14 Mbit/s and is restored (within ~2 minutes) by
cycling the modem band profile. Docker Compose stack; runs on any Docker host (a TrueNAS SCALE walkthrough is included).

Russian short version: [README.ru.md](README.ru.md)

## What it does
- Collects U5G radio/WAN metrics (unpoller), carrier aggregation (json_exporter), hourly speed tests (Speedtest Tracker), ICMP path metrics (blackbox).
- Every minute a **light probe** downloads 1 MB from DNA (judged by time; earlier detection, shadow mode by default). Every 5 min the **agent** downloads 5 MB from DNA's server (`nopeus.dna.fi`) and Cloudflare, measuring speed, RTT under
  load, big-packet (1472 B, DF) ping, receiver-side TCP out-of-order/DSACK counters, public IP.
- The **watchdog** declares an *episode* when the DNA probe is < 8 Mbit/s for 3 consecutive probes, then runs a read-only
  diagnostic bundle on the modem (`diag`) and - only in `live` mode - the cure (`cure`), re-measures, and records the result.
- Grafana dashboards + Telegram alerts. Everything is provisioned from files; no manual UI work.

## Safety model (read this)
- Default mode is **dry-run**: episodes are detected and diagnosed, the modem is never changed.
  Switch with `echo live > data/mode` (and back with `echo dry > data/mode`); no restart needed.
- The agent's SSH key on the modem is **restricted by a forced command**: it can only run `ping`, `diag`, `cure`.
- Cure rate limits: min 3 h between triggers, max 4 per day. No cure if the modem is unreachable.
- The cure depends on a **custom band profile `0D`** that must already exist on the modem (not part of the stock set; definition and `modem/create-profile-0d.sh` in docs/MODEM.md).
  If it is missing, `cure` refuses to run and changes nothing; the scripts always return the modem to profile `00`.
- Nothing is written to the modem's flash by this repo (see docs/MODEM.md for what that implies after a modem reboot).

## Layout
| Path | Purpose |
|---|---|
| `docker-compose.yml` | the whole stack: prometheus, grafana, blackbox, node-exporter (textfile only), unpoller, json-exporter, speedtest-tracker, agent |
| `agent/probe.sh`, `agent/watchdog.sh`, `agent/entrypoint.sh` | probes and watchdog (run inside the `agent` container) |
| `modem/` | scripts that live on the U5G: `u5g-dispatch.sh` (forced command), `band-cycle.sh` (the cure), `install-modem.sh` |
| `config/` | Prometheus, blackbox, json_exporter (template, key rendered by `scripts/init.sh`), Grafana provisioning (datasource, dashboards, alert rules, Telegram contact point) |
| `scripts/init.sh` | one-time bootstrap: `.env`, secrets, watchdog key, rendered Prometheus config |
| `AGENTS.md` | rules, invariants and checklists for automated agents (**read first if you are one**) |
| `docs/` | ARCHITECTURE, DEPLOY (agent runbook), TRUENAS, MODEM, OPERATIONS, FINDINGS, METRICS, KNOWN_GAPS, TROUBLESHOOTING, `episodes/` (recorded episodes) |

## Documentation reading order
1. **This README** - what the system is, the safety model, the layout.
2. **[AGENTS.md](AGENTS.md)** - mandatory if you are an automated agent: hard safety rules, invariants, pre-commit checks.
3. **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - components, data flow, and *why* it is built this way (modem is not a host for continuous work).
4. **[docs/KNOWN_GAPS.md](docs/KNOWN_GAPS.md)** - what was never verified or is missing; read before trusting anything.
5. **[docs/DEPLOY.md](docs/DEPLOY.md)** - step-by-step deployment with checks and done-criteria (TrueNAS SCALE: also [docs/TRUENAS.md](docs/TRUENAS.md)).
6. **[docs/MODEM.md](docs/MODEM.md)** - the U5G itself: filesystem, SSH, the cure, why the setup does not survive a modem reboot.
7. **[docs/OPERATIONS.md](docs/OPERATIONS.md)** - day-to-day: mode switch, manual diag/cure, episode playbook, tuning, backups.
8. **[docs/FINDINGS.md](docs/FINDINGS.md)** and **[docs/baselines/](docs/baselines/)** - the evidence: what the slow state is and is not, good-state reference numbers.
9. **[docs/METRICS.md](docs/METRICS.md)** - metric names and meanings (when touching dashboards or alerts).
10. **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - when something fails.

## Quick start
```bash
./scripts/init.sh                 # creates .env on first run -> edit it (Telegram, UniFi API key, Grafana password) -> re-run
modem/install-modem.sh <ssh_user>@<U5G_IP>   # installs dispatcher + restricted key on the modem (needs your admin ssh access)
docker compose up -d
```
Full, verifiable runbook: [docs/DEPLOY.md](docs/DEPLOY.md). Start there if you are an automated agent.

## Disclaimer
Personal project, shared as-is under the [MIT license](LICENSE). Not affiliated with or endorsed by Ubiquiti, DNA, Sierra Wireless or any
other vendor named here. The `cure` changes the modem's band profile and the SSH setup logs into a root-equivalent account on the modem:
read [docs/MODEM.md](docs/MODEM.md) and [docs/KNOWN_GAPS.md](docs/KNOWN_GAPS.md) first, keep `data/mode` on `dry` until you have seen an
episode, and use it at your own risk. The stack was validated syntactically and in part on a live system, not end-to-end from scratch (see KNOWN_GAPS).
Never commit `.env` or `data/` (both are git-ignored): they hold the Telegram token, UniFi API key and the watchdog SSH private key.
