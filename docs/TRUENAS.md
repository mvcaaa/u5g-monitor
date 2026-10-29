# Running on TrueNAS SCALE (tested environment: 25.04.2.6, Docker-based apps, pool `Main`, Intel N100)

TrueNAS is just a Docker host. Two layouts exist: **A** runs the whole stack from this repo with compose; **B** is the owner's box,
where the monitoring stack predates the repo as UI apps and the agent runs as a Custom App.

## A. Compose stack (recommended)
1. Enable SSH (System → Services → SSH) and add your public key to the admin user (Credentials → Local Users); enable passwordless sudo
   if you want unattended operation. Terminal-first: everything below is CLI.
2. Check Docker and compose: `sudo docker version && sudo docker compose version`. (If `compose` is missing, use A2 below.)
3. Put the repo on the pool (own dataset recommended so it can be snapshotted):
   ```bash
   sudo zfs create Main/u5g-monitor 2>/dev/null || true
   sudo git clone <this repo> /mnt/Main/u5g-monitor      # or scp/rsync the tree
   cd /mnt/Main/u5g-monitor && sudo ./scripts/init.sh    # edit .env, re-run (see DEPLOY.md)
   ```
4. **Port conflicts:** if the UI-managed apps of layout B still run, they hold 30037/30104/30220/30910 etc. The compose stack
   defaults to 3000/9090 - set `GRAFANA_PORT`, `PROMETHEUS_PORT` in `.env` to free ports, or stop the old apps first.
   Do not delete the old apps' datasets until the new stack has run for a while (history lives in their Prometheus volume).
5. `sudo docker compose up -d`, then `sudo ./scripts/verify.sh`.
6. Persistence: containers use `restart: unless-stopped`; Docker is started by TrueNAS on boot once an Apps pool is selected
   (Apps → Settings → Choose Pool). After a TrueNAS reboot run `verify.sh`.

Compose-run containers do not appear in the TrueNAS Apps UI; manage them with `docker compose` from `/mnt/Main/u5g-monitor`.

### A2. As a TrueNAS "Custom App" (Apps → Discover → Install via YAML)
Paste `docker-compose.yml`, but TrueNAS needs **absolute host paths**: replace `./config`, `./data` with
`/mnt/Main/u5g-monitor/config` etc., substitute the `${...}` variables (the UI does not read `.env`), and run `init.sh` on the host first.
The stack has no `build:` sections precisely so this works.

## B. Layout on the owner's TrueNAS (UI apps + the agent as a Custom App)
Rule: **nothing of this project runs on the TrueNAS OS itself** - no cron jobs, no scripts, no packages. Every component is a container;
the host only keeps the agent's data directory as a volume.
| Component | How | Port |
|---|---|---|
| Prometheus (container `ix-prometheus-prometheus-1`) | UI app; config `/mnt/.ix-apps/app_mounts/prometheus/config/prometheus.yml`; restart: `sudo docker restart ix-prometheus-prometheus-1` | 30104 |
| Grafana | UI app | 30037 |
| unpoller, blackbox (v0.29.0, `icmp` module), json_exporter (v0.8.0, config = `config/json_exporter/json_exporter.yml` with the key filled in) | UI apps | 9130, 9115, 7979 |
| node-exporter with textfile collector | Custom App `node-exporter`, textfile dir mounted from `/mnt/Main/u5g-watchdog/textfile` | 30910 |
| agent: probes, watchdog, episode/reference tests, radio snapshot | Custom App `u5g-agent` from `deploy/truenas-agent-app.yml`: image `ghcr.io/mvcaaa/u5g-agent` pinned by digest, host network, schedule `agent/crontab` (supercronic), volume `/mnt/Main/u5g-watchdog:/data` | |
| agent data | `/mnt/Main/u5g-watchdog`: `mode`, `id_u5g` (root:600), `known_hosts` (the modem's host key), `state/`, `diag/`, `radio/`, `textfile/`, `watchdog.log` | |
| Speedtest Tracker (stopped 2026-10-20, removed from the project) | UI app, kept stopped; no longer scraped | 30220 |

**Install / update the agent app:** fill the placeholders of `deploy/truenas-agent-app.yml` (digest of the image to run, modem address and
login, `/mnt/Main/u5g-watchdog`) and paste it in Apps -> Discover -> Install via YAML, or `midclt call app.create` with
`custom_compose_config_string`. Update = the same YAML with the new digest (`app.update`); rollback = the previous digest. The image is
pulled once at install, never during an episode.
**Look at it:** `sudo docker logs --tail 50 ix-u5g-agent-agent-1` (supercronic and job output), `/mnt/Main/u5g-watchdog/watchdog.log`;
run a script by hand: `sudo docker exec ix-u5g-agent-agent-1 bash /app/watchdog.sh` (or `env EPT_KIND=reference bash /app/episode-tests.sh`).
**Modem side** (from the workstation with admin access to the modem): copy `/mnt/Main/u5g-watchdog/id_u5g.pub` (public key only) to the
workstation and run `U5G_PUB=<that copy> bash modem/install-modem.sh <ssh_user>@<U5G_IP> [port]`.
**Migration from the former host cron jobs** (until 2026-10: TrueNAS cron jobs 1-5 ran copies of `agent/*.sh` from `/mnt/Main/u5g-watchdog`):
copy the modem's line from `/root/.ssh/known_hosts` to `/mnt/Main/u5g-watchdog/known_hosts`; delete the cron jobs
(`midclt call cronjob.delete <id>`, while holding `flock /mnt/Main/u5g-watchdog/state/lock`); install the app; check that `state/light.log`
grows every minute and `textfile/u5g_watchdog.prom` stays fresh; then remove the host copies of the scripts and their backups.
Never run both at once: they would both probe and could both trigger a cure.
