#!/bin/bash
# u5g-watchdog v1: detect "DNA slow" episodes from probe.sh data, run diag, optionally cure the modem.
# Mode file: $D/mode = dry (default: diag only, no cure) | live (diag + cure)
# Light-probe file: $D/light_mode = shadow (default: only log/metric when the light probe would have detected an episode)
#                              | primary (a light-probe episode triggers like the heavy one) | off
D=${D:-/data}
PROM=$D/textfile/u5g_probe.prom
OUTP=$D/textfile/u5g_watchdog.prom
ST=$D/state; HIST=$ST/history.log; SE=$ST/state.env; LOG=$D/watchdog.log
mkdir -p "$ST" "$D/diag"; touch "$HIST"
MODE=$(cat "$D/mode" 2>/dev/null || echo dry)
THRESH=${THRESH:-8000000}   # bit/s: DNA probe below this = slow
NEED=${NEED:-3}             # consecutive slow probes
MININT=${MININT:-10800}     # min seconds between triggers
MAXDAY=${MAXDAY:-4}         # max triggers per day
WAITAFTER=${WAITAFTER:-170} # seconds to wait after cure before re-measuring (the modem cycle itself holds 0D for 120 s, see docs/KNOWN_GAPS.md)
SSHC=${SSHC:-"ssh -p ${MODEM_SSH_PORT:-2222} -i $D/id_u5g -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new ${MODEM_USER:-admin}@${MODEM_HOST:?set MODEM_HOST}"}
PROBE=${PROBE:-$D/probe.sh}
LNEED=${LNEED:-3}           # light probe: consecutive slow samples (1 per minute)
LSLOW=${LSLOW:-2}           # light probe: a 1 MB download taking >= this many seconds is slow (good state: 0.3-0.8 s)
LAGE=${LAGE:-400}           # light probe: all samples must be this recent (s)
LMODE=$(cat "$D/light_mode" 2>/dev/null || echo shadow)

exec 9>"$ST/lock"; flock -n 9 || exit 0
log() { echo "$(date '+%F %T') [$MODE] $*" >> "$LOG"; }
now=$(date +%s)

LAST_TRIGGER=0; CURES_TOTAL=0; DRY_TOTAL=0; DAY=$(date +%F); DAY_COUNT=0; LAST_RESULT=-1; LAST_CURE_TS=0
LIGHT_ACTIVE=0; LIGHT_SINCE=0; LIGHT_TOTAL=0; LAST_SUPP=0
[ -f "$SE" ] && . "$SE"
save() {
  printf 'LAST_TRIGGER=%s\nCURES_TOTAL=%s\nDRY_TOTAL=%s\nDAY=%s\nDAY_COUNT=%s\nLAST_RESULT=%s\nLAST_CURE_TS=%s\nLIGHT_ACTIVE=%s\nLIGHT_SINCE=%s\nLIGHT_TOTAL=%s\nLAST_SUPP=%s\n' \
    "$LAST_TRIGGER" "$CURES_TOTAL" "$DRY_TOTAL" "$DAY" "$DAY_COUNT" "$LAST_RESULT" "$LAST_CURE_TS" "$LIGHT_ACTIVE" "$LIGHT_SINCE" "$LIGHT_TOTAL" "$LAST_SUPP" > "$SE.tmp" && mv "$SE.tmp" "$SE"
}
readprobe() {
  pts=$(awk '/^u5g_probe_last_run_timestamp_seconds/{print $2}' "$PROM" 2>/dev/null)
  dna=$(awk '/^u5g_probe_download_bits_per_second\{target="dna"\}/{print $2}' "$PROM" 2>/dev/null)
  code=$(awk '/^u5g_probe_http_code\{target="dna"\}/{print $2}' "$PROM" 2>/dev/null)
}

[ "$DAY" != "$(date +%F)" ] && { DAY=$(date +%F); DAY_COUNT=0; }

# 1. take a new sample if the probe produced one
readprobe
fresh=0; reach=-1; ep=0
if [ -n "$pts" ] && [ $((now - pts)) -lt 900 ]; then
  fresh=1
  last=$(tail -n 1 "$HIST" 2>/dev/null | awk '{print $1}')
  [ "$pts" != "$last" ] && echo "$pts ${dna:-0} ${code:-0}" >> "$HIST"
fi
tail -n 200 "$HIST" > "$HIST.tmp" 2>/dev/null && mv "$HIST.tmp" "$HIST"

# 2. episode condition: last NEED samples all HTTP 200, all slow, all recent
if [ "$(wc -l < "$HIST" 2>/dev/null || echo 0)" -ge "$NEED" ]; then
  ep=$(tail -n "$NEED" "$HIST" | awk -v th="$THRESH" -v now="$now" -v need="$NEED" \
    'BEGIN{ok=1;n=0} {n++; if($3!=200||$2>=th||now-$1>1500) ok=0} END{print (ok&&n==need)?1:0}')
fi

# 2b. light probe (1 MB, every minute): last LNEED samples all HTTP 200, all slow (time), all recent
lep=0; lfresh=0; lt=0; src=heavy; LL=$ST/light.log
if [ -s "$LL" ] && [ "$LMODE" != off ]; then
  lts=$(tail -n 1 "$LL" | awk '{print $1}'); lt=$(tail -n 1 "$LL" | awk '{print $2}')
  [ $((now - lts)) -lt 600 ] && lfresh=1
  if [ "$(wc -l < "$LL")" -ge "$LNEED" ]; then
    lep=$(tail -n "$LNEED" "$LL" | awk -v th="$LSLOW" -v now="$now" -v need="$LNEED" -v age="$LAGE" \
      'BEGIN{ok=1;n=0} {n++; if($3!=200||$2<th||now-$1>age) ok=0} END{print (ok&&n==need)?1:0}')
  fi
fi
if [ "$lep" = 1 ] && [ "$LIGHT_ACTIVE" != 1 ]; then
  LIGHT_ACTIVE=1; LIGHT_SINCE=$now; LIGHT_TOTAL=$((LIGHT_TOTAL + 1))
  log "LIGHT episode detected [$LMODE]: last $LNEED 1 MB probes took >= ${LSLOW}s (latest ${lt}s); heavy probe episode=$ep"
elif [ "$lep" = 0 ] && [ "$LIGHT_ACTIVE" = 1 ]; then
  LIGHT_ACTIVE=0
  log "LIGHT episode cleared after $((now - LIGHT_SINCE))s"
fi
[ "$LMODE" = primary ] && [ "$lep" = 1 ] && [ "$ep" != 1 ] && { ep=1; src=light; }

# 3. trigger
if [ "$ep" = 1 ] && [ $((now - LAST_TRIGGER)) -ge "$MININT" ] && [ "$DAY_COUNT" -lt "$MAXDAY" ]; then
  if $SSHC ping 2>/dev/null | grep -q pong; then
    reach=1
    LAST_TRIGGER=$now; DAY_COUNT=$((DAY_COUNT + 1))
    f="$D/diag/episode-$(date +%Y%m%d-%H%M).txt"
    if [ "$src" = light ]; then log "EPISODE (light probe): last $LNEED 1 MB probes took >= ${LSLOW}s (latest ${lt}s), running diag -> $f"
    else log "EPISODE: last $NEED probes below $THRESH bit/s (latest ${dna}), running diag -> $f"; fi
    timeout 220 $SSHC diag > "$f" 2>&1
    if [ "$MODE" = live ]; then
      CURES_TOTAL=$((CURES_TOTAL + 1)); LAST_CURE_TS=$(date +%s)
      log "CURE: sending cure, waiting ${WAITAFTER}s"
      $SSHC cure >> "$LOG" 2>&1
      sleep "$WAITAFTER"
      "$PROBE" >/dev/null 2>&1
      readprobe
      if [ "${code:-0}" = 200 ] && awk -v v="${dna:-0}" -v th="$THRESH" 'BEGIN{exit !(v>=th)}'; then LAST_RESULT=1; else LAST_RESULT=0; fi
      log "CURE result=$LAST_RESULT dna=${dna} bit/s code=${code}"
    else
      DRY_TOTAL=$((DRY_TOTAL + 1))
      log "DRY-RUN: would cure now (no action taken)"
    fi
    : > "$HIST"
    save
  else
    reach=0
    log "EPISODE detected but modem unreachable via ssh; skipping"
  fi
elif [ "$ep" = 1 ] && [ $((now - LAST_SUPP)) -ge 900 ]; then
  LAST_SUPP=$now
  log "EPISODE ongoing but suppressed (interval/day limit: last trigger $((now - LAST_TRIGGER))s ago, today $DAY_COUNT/$MAXDAY)"
fi
[ "$reach" = -1 ] && { $SSHC ping 2>/dev/null | grep -q pong && reach=1 || reach=0; }
save

# 4. metrics
{
  echo "u5g_watchdog_last_run_timestamp_seconds $(date +%s)"
  echo "u5g_watchdog_probe_fresh $fresh"
  echo "u5g_watchdog_episode_active $ep"
  echo "u5g_watchdog_modem_reachable $reach"
  echo "u5g_watchdog_live_mode $([ "$MODE" = live ] && echo 1 || echo 0)"
  echo "u5g_watchdog_cures_total $CURES_TOTAL"
  echo "u5g_watchdog_dryrun_triggers_total $DRY_TOTAL"
  echo "u5g_watchdog_last_cure_result $LAST_RESULT"
  echo "u5g_watchdog_last_cure_timestamp_seconds $LAST_CURE_TS"
  echo "u5g_watchdog_triggers_today $DAY_COUNT"
  echo "u5g_watchdog_light_fresh $lfresh"
  echo "u5g_watchdog_light_episode_active $lep"
  echo "u5g_watchdog_light_primary $([ "$LMODE" = primary ] && echo 1 || echo 0)"
  echo "u5g_watchdog_light_detections_total $LIGHT_TOTAL"
} > "$OUTP.tmp" && chmod 644 "$OUTP.tmp" && mv "$OUTP.tmp" "$OUTP"
