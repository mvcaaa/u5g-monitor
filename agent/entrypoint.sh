#!/bin/bash
# Loop: probe at t+0, watchdog at t+120s, period 300s. Watchdog may take longer (diag/cure) - the loop just waits.
mkdir -p /data/textfile /data/state /data/diag
[ -f /data/mode ] || echo dry > /data/mode
[ -f /data/id_u5g ] && chmod 600 /data/id_u5g
while true; do
  start=$(date +%s)
  /app/probe.sh  >>/data/agent.log 2>&1
  sleep 120
  /app/watchdog.sh >>/data/agent.log 2>&1
  date +%s > /data/state/heartbeat
  # keep the log bounded
  [ "$(stat -c %s /data/agent.log 2>/dev/null || echo 0)" -gt 5000000 ] && tail -n 2000 /data/agent.log > /data/agent.log.tmp && mv /data/agent.log.tmp /data/agent.log
  left=$(( 300 - ($(date +%s) - start) )); [ "$left" -gt 0 ] && sleep "$left"
done
