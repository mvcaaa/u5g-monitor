#!/bin/bash
# Post-deploy acceptance checks. Exit code 0 = all good. Run from the repo root on the Docker host.
cd "$(dirname "$0")/.."
get() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
P=http://localhost:$(get PROMETHEUS_PORT); P=${P%:}; [ "$P" = "http://localhost" ] && P=http://localhost:9090
G=http://localhost:$(get GRAFANA_PORT); [ "$G" = "http://localhost:" ] && G=http://localhost:3000
fail=0; ok() { echo "PASS  $*"; }; bad() { echo "FAIL  $*"; fail=1; }

for s in prometheus grafana blackbox node-exporter unpoller speedtest-tracker agent; do
  st=$(docker compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s=$s '$1==s{print $2}')
  [ "$st" = running ] && ok "container $s running" || bad "container $s state='$st'"
done
for j in prometheus unpoller speedtest_tracker blackbox_icmp node_textfile; do
  n=$(curl -s "$P/api/v1/targets?state=active" | grep -o "\"job\":\"$j\"[^}]*\"health\":\"up\"" | wc -l)
  [ "$n" -ge 1 ] && ok "prometheus target job=$j up ($n)" || bad "prometheus target job=$j not up (see docs/TROUBLESHOOTING.md)"
done
q() { curl -s "$P/api/v1/query" --data-urlencode "query=$1" | grep -c '"result":\[{'; }
for m in u5g_probe_download_bits_per_second u5g_probe_light_time_seconds u5g_watchdog_modem_reachable u5g_watchdog_live_mode; do
  [ "$(q $m)" = 1 ] && ok "metric $m present" || bad "metric $m missing (agent needs ~2-3 min after start)"
done
[ "$(q 'u5g_watchdog_modem_reachable == 1')" = 1 ] && ok "watchdog reaches the modem" || bad "modem not reachable by the agent (run modem/install-modem.sh)"
curl -s -u "$(get GRAFANA_ADMIN_USER):$(get GRAFANA_ADMIN_PASSWORD)" "$G/api/v1/provisioning/alert-rules" | grep -q 'u5g-cure-executed' \
  && ok "grafana alert rules provisioned" || bad "grafana alert rules missing"
curl -s -u "$(get GRAFANA_ADMIN_USER):$(get GRAFANA_ADMIN_PASSWORD)" "$G/api/search?query=U5G" | grep -q 'u5g-radio-monitor-en' \
  && ok "grafana dashboards provisioned" || bad "grafana dashboards missing"
echo "mode: $(cat data/mode 2>/dev/null)"; exit $fail
