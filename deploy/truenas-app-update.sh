#!/bin/bash
# Update the Custom App u5g-agent to another image digest (rollback = run with the previous digest). Prints no modem address or login.
# usage (on TrueNAS, with deploy/truenas-agent-app.yml copied to /tmp/u5g-agent-app.yml): sudo bash truenas-app-update.sh <sha256:...>
set -euo pipefail
DIGEST=${1:?usage: $0 sha256:...}
W=/mnt/Main/u5g-watchdog; TPL=/tmp/u5g-agent-app.yml
CUR=$(docker inspect ix-u5g-agent-agent-1 --format '{{range .Config.Env}}{{println .}}{{end}}')
MH=$(echo "$CUR" | sed -n 's/^MODEM_HOST=//p'); MU=$(echo "$CUR" | sed -n 's/^MODEM_USER=//p')
[ -n "$MH" ] && [ -n "$MU" ] || { echo "modem host/user not found in the running container"; exit 1; }
docker pull -q "ghcr.io/mvcaaa/u5g-agent@$DIGEST" >/dev/null && echo "image pulled"
YAML=$(sed -e "s|__DIGEST__|$DIGEST|" -e "s|__MODEM_HOST__|$MH|" -e "s|__MODEM_USER__|$MU|" -e "s|__DATA__|$W|" $TPL | grep -v '^#')
echo "$YAML" | grep -q '__' && { echo "placeholder left"; exit 1; }
echo "$YAML" | docker compose -p u5g-check -f - config -q && echo "compose YAML valid"
python3 -c 'import json,sys;print(json.dumps({"custom_compose_config_string":sys.stdin.read()}))' <<<"$YAML" > /tmp/u5g-app-upd.json
midclt call -j app.update u5g-agent "$(cat /tmp/u5g-app-upd.json)" >/dev/null && echo "app updated"
rm -f /tmp/u5g-app-upd.json
sleep 5
docker inspect ix-u5g-agent-agent-1 --format 'running image {{.Config.Image}} started {{.State.StartedAt}}'
