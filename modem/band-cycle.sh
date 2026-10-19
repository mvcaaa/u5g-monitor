#!/bin/sh
# "Cure": cycle the modem band profile 00 -> 0D -> 00 to force network re-registration (~2 min, no real outage).
# Profile 0D = "No n28 Test" (same masks as 00 but NR NSA without n28); 00 = all bands.
# NOTE: this is a RECONSTRUCTION of the user's live /etc/persistent/band-cycle.sh (634 bytes). The original's exact
# timings were not captured; if the live file differs, keep the live one (see docs/KNOWN_GAPS.md).
# Never run in a healthy state without a reason. Invoked by u5g-dispatch.sh as: nohup sh band-cycle.sh &
LOG=/tmp/log/band-cycle.log   # /tmp/log is a persistent ext4 partition on the U5G
mkdir -p /tmp/log
AT() { uiwwand-chat -t 10 "$1" 2>&1; }
{
  echo "=== $(date '+%F %T') band cycle start; profile before: $(AT 'AT!BAND?' | tr '\n' ' ')"
  AT 'AT!BAND=0D'
  sleep 20
  AT 'AT!BAND=00'
  sleep 5
  echo "=== $(date '+%F %T') done; profile now: $(AT 'AT!BAND?' | tr '\n' ' ')"
} >> "$LOG" 2>&1
