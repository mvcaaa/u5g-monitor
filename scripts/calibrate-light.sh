#!/bin/bash
# Good-state calibration of a light DNA probe: N downloads of SIZE bytes, prints code, time_total (s), Mbit/s. Usage: bash calibrate-light.sh [size_bytes] [count]
SIZE=${1:-1000000}; N=${2:-20}; URL="http://nopeus.dna.fi:8080/download?size=$SIZE"
echo "### calibrate $(date '+%F %T') size=$SIZE n=$N"
for i in $(seq 1 "$N"); do
  curl -s -m 8 -o /dev/null -w '%{http_code} %{time_total} %{speed_download}\n' "$URL" | awk -v i="$i" '{printf "%2d code=%s t=%.2fs %.1f Mbit/s\n", i, $1, $2, $3*8/1e6}'
  sleep 3
done
