#!/bin/bash
# u5g-probe v3: download probes + idle/big DF ping + loaded ping + TCP receiver counters + public IP
# writes a Prometheus textfile for node_exporter (atomic rename)
DIR=${DIR:-/data}
OUT=$DIR/textfile/u5g_probe.prom
SIZE=${SIZE:-5000000}
MAXT=${MAXT:-8}
PINGHOST=${PINGHOST:-nopeus.dna.fi}
DNA_URL=${DNA_URL:-http://nopeus.dna.fi:8080/download?size=$SIZE}
CF_URL=${CF_URL:-https://speed.cloudflare.com/__down?bytes=$SIZE}
PF=$(mktemp)
trap 'rm -f "$PF"' EXIT

# nstat FILE PREFIX FIELD -> value of FIELD in the "PREFIX:" table of FILE
nstat() {
  awk -v p="$2:" -v k="$3" '$1==p{if(!h){for(i=2;i<=NF;i++)n[$i]=i;h=1}else{print $(n[k]);exit}}' "$1"
}

probe() {
  local name=$1 url=$2 r code bytes bps tt
  r=$(curl -s -L -m "$MAXT" -o /dev/null -w '%{http_code} %{size_download} %{speed_download} %{time_total}' "$url" 2>/dev/null)
  read -r code bytes bps tt <<<"${r:-000 0 0 0}"
  echo "u5g_probe_http_code{target=\"$name\"} $code"
  echo "u5g_probe_bytes{target=\"$name\"} $bytes"
  echo "u5g_probe_download_bits_per_second{target=\"$name\"} $(awk -v b="$bps" 'BEGIN{printf "%.0f", b*8}')"
  echo "u5g_probe_duration_seconds{target=\"$name\"} $tt"
}

{
  echo "# TYPE u5g_probe_download_bits_per_second gauge"

  # DNA probe with a parallel ping (loaded RTT) and receiver-side TCP counters
  ofo0=$(nstat /proc/net/netstat TcpExt TCPOFOQueue)
  da=$(nstat /proc/net/netstat TcpExt TCPDSACKOldSent); db=$(nstat /proc/net/netstat TcpExt TCPDSACKOfoSent)
  dsk0=$(( ${da:-0} + ${db:-0} ))
  in0=$(nstat /proc/net/snmp Tcp InSegs)
  ping -c 6 -i 0.5 -W 2 -q "$PINGHOST" >"$PF" 2>&1 &
  PP=$!
  probe dna "$DNA_URL"
  wait $PP 2>/dev/null
  ofo1=$(nstat /proc/net/netstat TcpExt TCPOFOQueue)
  da=$(nstat /proc/net/netstat TcpExt TCPDSACKOldSent); db=$(nstat /proc/net/netstat TcpExt TCPDSACKOfoSent)
  dsk1=$(( ${da:-0} + ${db:-0} ))
  in1=$(nstat /proc/net/snmp Tcp InSegs)
  echo "u5g_probe_tcp_in_segments $(( in1 - in0 ))"
  echo "u5g_probe_tcp_ofo_queued $(( ofo1 - ofo0 ))"
  echo "u5g_probe_tcp_dsack_sent $(( dsk1 - dsk0 ))"
  awk -F'[/ =]+' '/^rtt/{printf "u5g_probe_loaded_rtt_avg_seconds %.6f\nu5g_probe_loaded_rtt_max_seconds %.6f\n", $7/1000, $8/1000}' "$PF"
  awk -F', ' '/packet loss/{sub(/%.*/,"",$3); printf "u5g_probe_loaded_loss_ratio %.4f\n", $3/100}' "$PF"

  probe cloudflare "$CF_URL"

  for sz in 56 1472; do
    pf=$(ping -c 5 -i 0.3 -W 2 -q -M do -s $sz "$PINGHOST" 2>&1)
    echo "$pf" | awk -F', ' -v s=$sz '/packet loss/{sub(/%.*/,"",$3); printf "u5g_probe_ping_loss_ratio{size=\"%s\"} %.4f\n", s, $3/100}'
    echo "$pf" | awk -F'[/ =]+' -v s=$sz '/^rtt/{printf "u5g_probe_ping_rtt_avg_seconds{size=\"%s\"} %.6f\n", s, $7/1000}'
  done

  ip=$(curl -s -m 5 https://api.ipify.org 2>/dev/null)
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "u5g_public_ip_info{ip=\"$ip\"} 1"
  fi
  echo "u5g_probe_last_run_timestamp_seconds $(date +%s)"
} > "$OUT.tmp"
chmod 644 "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
