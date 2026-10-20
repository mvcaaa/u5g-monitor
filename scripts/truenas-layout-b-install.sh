#!/bin/bash
# TrueNAS layout B (hand-built, cron based; see docs/TRUENAS.md): install/update the agent scripts and their cron jobs. Idempotent. Run as root from a repo checkout.
# usage: sudo MODEM_HOST=<modem ip> [MODEM_USER=admin] [MODEM_SSH_PORT=2222] [D=/mnt/Main/u5g-watchdog] bash scripts/truenas-layout-b-install.sh
# Starts in mode=dry (the file is only created when missing). The 5-minute probe.sh job of older installs is disabled. The old watchdog.sh is kept once as watchdog.sh.v1.
set -e
: "${MODEM_HOST:?set MODEM_HOST}"
MODEM_USER=${MODEM_USER:-admin}; MODEM_SSH_PORT=${MODEM_SSH_PORT:-2222}; D=${D:-/mnt/Main/u5g-watchdog}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$D/state" "$D/diag" "$D/textfile"
[ -f "$D/watchdog.sh" ] && [ ! -f "$D/watchdog.sh.v1" ] && ! cmp -s "$HERE/agent/watchdog.sh" "$D/watchdog.sh" && cp -p "$D/watchdog.sh" "$D/watchdog.sh.v1"
for f in probe-light.sh watchdog.sh; do install -m 755 "$HERE/agent/$f" "$D/$f"; done
[ -f "$D/mode" ] || echo dry > "$D/mode"
ENVS="env D=$D DIR=$D MODEM_HOST=$MODEM_HOST MODEM_USER=$MODEM_USER MODEM_SSH_PORT=$MODEM_SSH_PORT"
job() { # script minute-field description
  cmd="$ENVS $D/$1"
  sched="{\"minute\":\"$2\",\"hour\":\"*\",\"dom\":\"*\",\"month\":\"*\",\"dow\":\"*\"}"
  id=$(midclt call cronjob.query "[[\"description\",\"=\",\"$3\"]]" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
  body="{\"user\":\"root\",\"command\":\"$cmd\",\"description\":\"$3\",\"enabled\":true,\"stdout\":false,\"stderr\":true,\"schedule\":$sched}"
  if [ -n "$id" ]; then midclt call cronjob.update "$id" "$body" >/dev/null; echo "updated cron $id: $3"; else midclt call cronjob.create "$body" >/dev/null; echo "created cron: $3"; fi
}
id=$(midclt call cronjob.query '[["description","=","u5g probe"]]' | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["id"] if d else "")')
if [ -n "$id" ]; then midclt call cronjob.update "$id" '{"enabled":false}' >/dev/null; echo "disabled cron $id: u5g probe (probe.sh is retired)"; fi
rm -f "$D/textfile/u5g_probe.prom"
job probe-light.sh '*' 'u5g light probe'
job watchdog.sh '*' 'u5g watchdog'
echo "mode: $(cat $D/mode)"
echo "NOTE: an older hand-made job for the same script (matched by command, not description) must be disabled to avoid double runs: midclt call cronjob.query"
