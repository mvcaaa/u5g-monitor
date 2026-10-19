#!/bin/sh
# Manual: cycle band profile 00 -> 0D -> 00 to force network reselection.
# Usage: nohup sh /etc/persistent/band-cycle.sh [wait_sec] >/dev/null 2>&1 &
# This is the owner's live script (captured 2026-10-19) plus ONE addition: the guard below that aborts when the custom
# profile 0D is not defined on the modem (see docs/MODEM.md and modem/create-profile-0d.sh).
# Timeline: 0D is set immediately, held for wait_sec (default 120 s), then 00 is set by the EXIT trap -> one cycle takes >= 2 minutes,
# plus re-registration time on 00. The EXIT trap also restores 00 if the script is interrupted by HUP/INT/TERM.
W=${1:-120}
LOG=${LOG:-/tmp/band-cycle.log}
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
if ! uiwwand-chat -t 5 'AT!BAND=?' 2>&1 | grep -q '^0D,'; then
  say "ABORT: custom profile 0D is not defined on this modem - nothing changed"
  exit 3
fi
finish() {
  trap - EXIT
  say "set 00 (All bands)"
  uiwwand-chat -t 10 'AT!BAND=00' >> "$LOG" 2>&1
  uiwwand-chat -t 5 'AT!BAND?' 2>&1 | head -3 >> "$LOG"
  say "done"
}
trap 'exit 1' HUP INT TERM
trap finish EXIT
say "start, current:"
uiwwand-chat -t 5 'AT!BAND?' 2>&1 | head -3 >> "$LOG"
say "set 0D (No n28 Test), wait ${W}s"
uiwwand-chat -t 10 'AT!BAND=0D' >> "$LOG" 2>&1
sleep "$W"
