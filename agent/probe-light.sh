#!/bin/bash
# u5g light probe: ONE small download from DNA per run (default 1 MB), judged by its TIME, not by speed:
# TCP slow start makes the average speed of a 1 MB file misleading (10-26 Mbit/s even in the good state).
# Output: $D/textfile/u5g_probe_light.prom (metrics) and $D/state/light.log ("<unix_ts> <time_total_s> <http_code> <bytes>", last 200 lines).
D=${D:-/data}
OUT=$D/textfile/u5g_probe_light.prom
LOGF=$D/state/light.log
SIZE=${LIGHT_SIZE:-1000000}
MAXT=${LIGHT_MAXT:-5}
URL=${LIGHT_URL:-http://nopeus.dna.fi:8080/download?size=$SIZE}
mkdir -p "$D/textfile" "$D/state"
r=$(curl -s -L -m "$MAXT" -o /dev/null -w '%{http_code} %{size_download} %{time_total}' "$URL" 2>/dev/null)
set -- $r
code=${1:-0}; bytes=${2:-0}; t=${3:-0}
ts=$(date +%s)
echo "$ts $t $code $bytes" >> "$LOGF"
tail -n 200 "$LOGF" > "$LOGF.tmp" 2>/dev/null && mv "$LOGF.tmp" "$LOGF"
bps=$(awk -v b="$bytes" -v t="$t" 'BEGIN{printf "%.0f", (t>0) ? b*8/t : 0}')
{
  echo "u5g_probe_light_last_run_timestamp_seconds $ts"
  echo "u5g_probe_light_http_code $code"
  echo "u5g_probe_light_bytes $bytes"
  echo "u5g_probe_light_time_seconds $t"
  echo "u5g_probe_light_download_bits_per_second $bps"
} > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
