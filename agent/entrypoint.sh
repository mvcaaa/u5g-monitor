#!/bin/bash
# Loop, period 60 s: light probe (the episode detector), diagnostic probe every 5th cycle, then the watchdog (flock-protected).
# The watchdog may take minutes during diag/cure - the loop simply waits and the following cycle starts late.
mkdir -p /data/textfile /data/state /data/diag
[ -f /data/mode ] || echo dry > /data/mode
[ -f /data/id_u5g ] && chmod 600 /data/id_u5g
i=0
while true; do
  start=$(date +%s)
  /app/probe-light.sh >>/data/agent.log 2>&1
  [ $((i % 5)) -eq 0 ] && /app/probe.sh >>/data/agent.log 2>&1
  [ $((i % 5)) -eq 2 ] && bash /app/radio-status.sh >>/data/agent.log 2>&1
  i=$((i + 1))
  /app/watchdog.sh >>/data/agent.log 2>&1
  # good-state reference of the episode tests at about 04:10 and 16:10 (skipped by the script during an episode)
  case "$(date +%H)" in 04|16) [ "$(date +%M)" -ge 10 ] && [ $(( $(date +%s) - $(cat /data/state/eptest-ref 2>/dev/null || echo 0) )) -gt 21600 ] &&
    { date +%s > /data/state/eptest-ref; EPT_KIND=reference bash /app/episode-tests.sh >>/data/agent.log 2>&1 & } ;; esac
  date +%s > /data/state/heartbeat
  # keep the log bounded
  [ "$(stat -c %s /data/agent.log 2>/dev/null || echo 0)" -gt 5000000 ] && tail -n 2000 /data/agent.log > /data/agent.log.tmp && mv /data/agent.log.tmp /data/agent.log
  left=$(( 60 - ($(date +%s) - start) )); [ "$left" -gt 0 ] && sleep "$left"
done
