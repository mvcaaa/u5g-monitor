# Deployment runbook (for a human or an automated agent with no prior context)

Goal: a running stack where `scripts/verify.sh` exits 0, in **dry-run** mode. Do not switch to `live` as part of deployment.
Time: ~15 min plus the first scrape cycles. Each step has a check; do not continue past a failed check.

## 0. Prerequisites
- Docker Engine with Compose v2 (`docker compose version`). Host has outbound internet (image pulls, `speed.cloudflare.com`, `nopeus.dna.fi:8080`, `api.ipify.org`, Telegram API).
- The host can reach the modem's management IP (`U5G_IP` in `.env`, required) and the UniFi controller URL.
- **Admin SSH access to the modem** that you can already use from some workstation: the admin user (uid 0, home `/etc/persistent`; name = `U5G_SSH_USER`),
  either key/password on port 22 or key on port 2222. Needed once, for `modem/install-modem.sh`.
- The custom band profile **`0D`** must already exist on the modem (`AT!BAND=?` lists `0D, No n28 Test`; see docs/MODEM.md). Without it the stack still monitors, but `cure` is refused; the owner can create it with `modem/create-profile-0d.sh` (docs/MODEM.md).
- A Telegram bot token (BotFather) and the numeric chat id (message the bot, then `curl https://api.telegram.org/bot<TOKEN>/getUpdates`).
- A **read-only** UniFi API key (UniFi Network → Settings → Control Plane → Integrations).
Never paste secrets into chat logs, tickets or commits. `.env` and `data/` are git-ignored.

## 1. Bootstrap
```bash
./scripts/init.sh            # 1st run: creates .env and stops; edit it; 2nd run: generates secrets + key, renders Prometheus config
```
Edit `.env`: `U5G_IP`, `GRAFANA_ADMIN_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `UNIFI_URL`, `UNIFI_API_KEY`.
Check: `ls data/id_u5g data/id_u5g.pub config/prometheus/prometheus.rendered.yml` all exist; `grep SPEEDTEST_APP_KEY .env` is non-empty.

## 2. Install the restricted key and scripts on the modem
```bash
modem/install-modem.sh <ssh_user>@<U5G_IP> [admin_ssh_port]     # asks for the admin credentials (several ssh calls)
ssh -p 2222 -i data/id_u5g -o BatchMode=yes -o StrictHostKeyChecking=accept-new <ssh_user>@<U5G_IP> ping     # expect: pong
ssh -p 2222 -i data/id_u5g -o BatchMode=yes <ssh_user>@<U5G_IP> id                                            # expect: denied
```
If the first prints `Permission denied (publickey,password)` see TROUBLESHOOTING (port 22 vs 2222). `install-modem.sh` does **not** write flash.
The first argument may also be an ssh alias from `~/.ssh/config` (its port is used unless you pass one). To run it from another machine than the one holding `data/`, set `U5G_PUB` to a copy of the watchdog public key (`id_u5g.pub` only, never the private key).

## 3. Start
```bash
docker compose up -d
```
The agent installs its packages on first start (needs internet, ~20 s). Wait ~3 min for the first probe+watchdog cycle.

## 4. One-time manual steps in Speedtest Tracker (UI, `http://<host>:8080`)
Default login for the linuxserver image is documented upstream (verify; typically `admin@example.com` / `password` - change it).
Settings → Data Integration → Prometheus: must be **enabled** and allow the docker subnet (compose sets
`PROMETHEUS_ENABLED`/`PROMETHEUS_ALLOWED_IPS`; if `/prometheus` returns 403 to Prometheus, add the container network's CIDR
(`docker network inspect u5g_default`). Run one manual test so metrics exist (before the first test `/prometheus` says "# no data available").

## 5. Verify
```bash
./scripts/verify.sh          # exit 0 expected; FAIL lines tell which doc section to read
docker compose logs agent --tail 30
```
Then open Grafana (`http://<host>:3000`, folder **U5G**): dashboard "U5G Radio Monitor (EN)"; the Watchdog row
should show Mode `dry-run`, Modem ssh `ok`, Episode `none`. Alerting → Alert rules: 8 rules in group `u5g`, all Normal.
Test Telegram: Alerting → Contact points → `telegram` → Test.

## 6. Done criteria
`verify.sh` exit 0, Telegram test message received, `data/mode` contains `dry`. Report: what passed, the modem-reboot caveat
(MODEM.md), and the known gaps (KNOWN_GAPS.md). Do not enable `live` without the owner's explicit approval after reviewing at least one dry-run episode.

## Rollback / removal
`docker compose down` (add `-v` to delete Prometheus/Grafana/Speedtest data). Modem: remove the `u5g-watchdog` line from
`/etc/persistent/.ssh/authorized_keys`, delete `/etc/persistent/u5g-dispatch.sh`, `pkill -f 'dropbear.*-p 2222'`.
