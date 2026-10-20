#!/bin/bash
# Loop, period 60 s: light probe, then the watchdog (flock-protected).
# The watchdog may take minutes during diag/cure - the loop simply waits and the following cycle starts late.
mkdir -p /data/textfile /data/state /data/diag
[ -f /data/mode ] || echo dry > /data/mode
[ -f /data/id_u5g ] && chmod 600 /data/id_u5g
while true; do
  start=$(date +%s)
  /app/probe-light.sh >>/data/agent.log 2>&1
  /app/watchdog.sh >>/data/agent.log 2>&1
  date +%s > /data/state/heartbeat
  # keep the log bounded
  [ "$(stat -c %s /data/agent.log 2>/dev/null || echo 0)" -gt 5000000 ] && tail -n 2000 /data/agent.log > /data/agent.log.tmp && mv /data/agent.log.tmp /data/agent.log
  left=$(( 60 - ($(date +%s) - start) )); [ "$left" -gt 0 ] && sleep "$left"
done
