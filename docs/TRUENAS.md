# Running on TrueNAS SCALE (tested environment: 25.04.2.6, Docker-based apps, pool `Main`, Intel N100)

TrueNAS is just a Docker host. Two layouts exist; **A is what this repo ships**, **B is how the project was first built by hand**
and is documented so an operator can recognise it on the box.

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
4. **Port conflicts:** if the old UI-managed apps (layout B) still run, they hold 30037/30104/30220/30910 etc. The compose stack
   defaults to 3000/9090/8080 - set `GRAFANA_PORT`, `PROMETHEUS_PORT`, `SPEEDTEST_PORT` in `.env` to free ports, or stop the old apps first.
   Do not delete the old apps' datasets until the new stack has run for a while (history lives in their Prometheus volume).
5. `sudo docker compose up -d`, then `sudo ./scripts/verify.sh`.
6. Persistence: containers use `restart: unless-stopped`; Docker is started by TrueNAS on boot once an Apps pool is selected
   (Apps → Settings → Choose Pool). After a TrueNAS reboot run `verify.sh`.

Compose-run containers do not appear in the TrueNAS Apps UI; manage them with `docker compose` from `/mnt/Main/u5g-monitor`.

### A2. As a TrueNAS "Custom App" (Apps → Discover → Install via YAML)
Paste `docker-compose.yml`, but TrueNAS needs **absolute host paths**: replace `./config`, `./agent`, `./data` with
`/mnt/Main/u5g-monitor/config` etc., substitute the `${...}` variables (the UI does not read `.env`), and run `init.sh` on the host first.
The stack has no `build:` sections precisely so this works.

## B. Layout the project was first deployed with (hand-built, UI apps + cron)
Useful to know when you find it on the box; this repo supersedes it.
| Component | How | Port |
|---|---|---|
| Prometheus (container `ix-prometheus-prometheus-1`) | UI app; config `/mnt/.ix-apps/app_mounts/prometheus/config/prometheus.yml`; restart: `sudo docker restart ix-prometheus-prometheus-1` | 30104 |
| Grafana | UI app | 30037 |
| Speedtest Tracker | UI app, `SPEEDTEST_SCHEDULE=7 * * * *`, servers 14164,22669,14928 | 30220 |
| unpoller, blackbox (v0.29.0, `icmp` module), json_exporter | UI apps | 9130, 9115, 7979 |
| node-exporter with textfile collector | UI app, textfile dir mounted from `/mnt/Main/u5g-watchdog/textfile` | 30910 |
| `probe.sh` | `/mnt/Main/u5g-watchdog/probe.sh`, TrueNAS cron job id 1, every 5 min | |
| `watchdog.sh` + state | `/mnt/Main/u5g-watchdog/`, cron job id 2 (`2-59/5 * * * *`), mode file `/mnt/Main/u5g-watchdog/mode` | |
| watchdog SSH key | `/mnt/Main/u5g-watchdog/id_u5g` | |
Cron on TrueNAS must be created via UI or `midclt call cronjob.create '{...}'` (not `crontab -e`). In layout B the scripts used
`D=/mnt/Main/u5g-watchdog`; in this repo they use `/data` inside the agent container (same file layout).
**Migrating B → A:** copy `id_u5g*` and `mode` into `data/`, stop cron jobs 1 and 2 (`midclt call cronjob.update <id> '{"enabled":false}'`),
then deploy A. Otherwise both would probe and could both trigger a cure.
