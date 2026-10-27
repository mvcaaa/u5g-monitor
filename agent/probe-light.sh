#!/bin/bash
# u5g light probe: ONE small download from DNA per run (default 1 MB), judged by its TIME, not by speed:
# TCP slow start makes the average speed of a 1 MB file misleading (10-26 Mbit/s even in the good state).
# While curl downloads, `ss` is polled for its socket: out-of-order data packets received (rcv_ooopack) and data segments in.
# Episodes reorder packets (150-200 per 1 MB), the good state does not; without `ss` both are 0. curl alone decides time and code.
# Output: $D/textfile/u5g_probe_light.prom (metrics) and $D/state/light.log
# ("<unix_ts> <time_total_s> <http_code> <bytes> <ooo_packets> <data_segs_in>", last 200 lines).
D=${D:-/data}
OUT=$D/textfile/u5g_probe_light.prom
LOGF=$D/state/light.log
SIZE=${LIGHT_SIZE:-1000000}
MAXT=${LIGHT_MAXT:-5}
URL=${LIGHT_URL:-http://nopeus.dna.fi:8080/download?size=$SIZE}
mkdir -p "$D/textfile" "$D/state"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -s -L -m "$MAXT" -o /dev/null -w '%{http_code} %{size_download} %{time_total} %{local_port}' "$URL" > "$T/r" 2>/dev/null &
pid=$!
dport=$(echo "$URL" | sed -nE 's#^[a-z]+://[^/:]+:([0-9]+).*#\1#p'); dport=${dport:-80}
if command -v ss >/dev/null 2>&1; then
  # "<local_port> <ooo> <segs>" per socket to that port, last poll wins (the counters only grow)
  while kill -0 "$pid" 2>/dev/null; do
    ss -Htin state established "( dport = :$dport )" 2>/dev/null | awk '
      /^[0-9]/ {n=split($(NF-1),a,":"); p=a[n]; next}
      p != "" {o=0; s=0; for(i=1;i<=NF;i++){ if($i ~ /^rcv_ooopack:/){split($i,b,":"); o=b[2]} if($i ~ /^data_segs_in:/){split($i,b,":"); s=b[2]} }
               print p, o, s; p=""}' >> "$T/ss"
    sleep 0.1
  done
fi
wait "$pid"
set -- $(cat "$T/r")
code=${1:-0}; bytes=${2:-0}; t=${3:-0}; lport=${4:-0}
set -- $(awk -v p="$lport" '$1==p {o=$2; s=$3} END{print o+0, s+0}' "$T/ss" 2>/dev/null)
ooo=${1:-0}; segs=${2:-0}
ts=$(date +%s)
echo "$ts $t $code $bytes $ooo $segs" >> "$LOGF"
tail -n 200 "$LOGF" > "$LOGF.tmp" 2>/dev/null && mv "$LOGF.tmp" "$LOGF"
bps=$(awk -v b="$bytes" -v t="$t" 'BEGIN{printf "%.0f", (t>0) ? b*8/t : 0}')
{
  echo "u5g_probe_light_last_run_timestamp_seconds $ts"
  echo "u5g_probe_light_http_code $code"
  echo "u5g_probe_light_bytes $bytes"
  echo "u5g_probe_light_time_seconds $t"
  echo "u5g_probe_light_download_bits_per_second $bps"
  echo "u5g_probe_light_ooo_packets $ooo"
  echo "u5g_probe_light_data_segs_in $segs"
} > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
