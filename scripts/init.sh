#!/bin/bash
# One-time bootstrap (idempotent): .env, secrets, watchdog key, rendered prometheus config, data dirs.
set -e
cd "$(dirname "$0")/.."
[ -f .env ] || { cp .env.example .env; echo "created .env - EDIT IT (U5G_IP, Telegram, UniFi, Grafana password), then re-run"; exit 0; }
get() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
U5G_IP=$(get U5G_IP)
mkdir -p data/textfile data/state data/diag
[ -f data/mode ] || echo dry > data/mode
if [ ! -f data/id_u5g ]; then
  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -q -t ed25519 -N '' -C u5g-watchdog -f data/id_u5g
  else   # no openssh on the host: use a throwaway alpine container
    docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/data:/data" alpine:3.20 sh -c "apk add --no-cache openssh-keygen >/dev/null 2>&1 || apk add --no-cache openssh-client >/dev/null; ssh-keygen -q -t ed25519 -N '' -C u5g-watchdog -f /data/id_u5g" || true
  fi
  [ -f data/id_u5g ] || { echo "ERROR: could not generate data/id_u5g (install openssh-client or start docker)"; exit 1; }
  echo "generated data/id_u5g (watchdog key)"
fi
chmod 600 data/id_u5g
UNIFI_URL=$(get UNIFI_URL)
sed -e "s/__U5G_IP__/${U5G_IP:?U5G_IP missing in .env}/" -e "s|__UNIFI_URL__|${UNIFI_URL:?UNIFI_URL missing in .env}|" \
  config/prometheus/prometheus.yml > config/prometheus/prometheus.rendered.yml
# json_exporter reads the UniFi API key from its config file only; awk keeps any characters of the key literal.
# 644: the container runs as nobody and must read it.
K="$(get UNIFI_API_KEY)" awk '/__UNIFI_API_KEY__/{sub(/__UNIFI_API_KEY__.*/,""); print $0 ENVIRON["K"]; next} 1' \
  config/json_exporter/json_exporter.yml > config/json_exporter/json_exporter.rendered.yml
chmod 644 config/json_exporter/json_exporter.rendered.yml
[ -n "$(get UNIFI_API_KEY)" ] || echo "WARNING: UNIFI_API_KEY is empty in .env - json-exporter (u5g_ca_*) and unpoller will fail"
echo "ok. next: install the key on the modem (modem/install-modem.sh), then: docker compose up -d --build"
