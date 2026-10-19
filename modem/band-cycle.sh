#!/bin/sh
# "Cure": cycle the modem band profile 00 -> 0D -> 00 to force network re-registration (~2 min, no real outage).
# Profile 0D "No n28 Test" is a CUSTOM profile created by the owner - it does NOT exist on a stock modem.
# It equals 00 except that NR NSA has n28 cleared (see docs/baselines/band-profiles.txt). Without 0D this script aborts and changes nothing.
# Safety: if the script is stopped by INT/TERM/HUP after 0D was set, 00 is restored on exit (the shell runs the trap after the current
# `sleep` ends, i.e. within $WAIT s). SIGKILL cannot be handled - verify with `AT!BAND?` if you ever kill it by hand.
# NOTE: reconstruction of the owner's live /etc/persistent/band-cycle.sh (634 bytes); exact original timings were not captured (docs/KNOWN_GAPS.md).
# Never run in a healthy state without a reason. Invoked by u5g-dispatch.sh as: nohup sh band-cycle.sh &
LOG=${LOG:-/tmp/log/band-cycle.log}   # /tmp/log is a persistent ext4 partition on the U5G
WAIT=${CYCLE_WAIT:-20}
mkdir -p "$(dirname "$LOG")"
AT() { uiwwand-chat -t 10 "$1" 2>&1; }
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

if ! AT 'AT!BAND=?' | grep -q '^0D,'; then
  log "ABORT: custom profile 0D is not defined on this modem - nothing changed"
  exit 3
fi
restore() { AT 'AT!BAND=00' >> "$LOG" 2>&1; log "restored profile 00 (exit trap)"; }
trap restore EXIT
trap 'exit 1' INT TERM HUP   # a signal ends the script; the EXIT trap then restores 00
log "start; profile before: $(AT 'AT!BAND?' | head -1 | tr '\n' ' ')"
AT 'AT!BAND=0D' >> "$LOG" 2>&1
sleep "$WAIT"
AT 'AT!BAND=00' >> "$LOG" 2>&1
trap - EXIT INT TERM HUP   # normal path: 00 is already set
sleep 5
log "done; profile now: $(AT 'AT!BAND?' | head -1 | tr '\n' ' ')"
