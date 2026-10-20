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
LNEED=${LNEED:-3}           # light probe: consecutive slow samples (1 per minute) to detect
LOUT=${LOUT:-5}             # light probe: consecutive fast samples to clear
LK=${LK:-4}                 # light probe: slow = time >= max(LK x baseline, LFLOOR)
LFLOOR=${LFLOOR:-1.5}       # light probe: threshold floor (s); good state 0.3-0.8 s, episode 3.5-5 s (capped by LIGHT_MAXT)
LBMIN=${LBMIN:-30}          # baseline: samples needed before it replaces LBDEF
LBDEF=${LBDEF:-0.5}         # baseline: default (s)
LBMAX=${LBMAX:-1.2}         # baseline: clamp, keeps LK x baseline below the 5 s probe timeout
LBWIN=${LBWIN:-1440}        # baseline: last N fast samples taken outside light episodes (~24 h)
LAGE=${LAGE:-400}           # light probe: samples older than this (s) are ignored
LMODE=$(cat "$D/light_mode" 2>/dev/null || echo shadow)

exec 9>"$ST/lock"; flock -n 9 || exit 0
log() { echo "$(date '+%F %T') [$MODE] $*" >> "$LOG"; }
now=$(date +%s)

LAST_TRIGGER=0; CURES_TOTAL=0; DRY_TOTAL=0; DAY=$(date +%F); DAY_COUNT=0; LAST_RESULT=-1; LAST_CURE_TS=0
LIGHT_ACTIVE=0; LIGHT_SINCE=0; LIGHT_TOTAL=0; LAST_SUPP=0; LBASE_TS=0
[ -f "$SE" ] && . "$SE"
save() {
  printf 'LAST_TRIGGER=%s\nCURES_TOTAL=%s\nDRY_TOTAL=%s\nDAY=%s\nDAY_COUNT=%s\nLAST_RESULT=%s\nLAST_CURE_TS=%s\nLIGHT_ACTIVE=%s\nLIGHT_SINCE=%s\nLIGHT_TOTAL=%s\nLAST_SUPP=%s\nLBASE_TS=%s\n' \
    "$LAST_TRIGGER" "$CURES_TOTAL" "$DRY_TOTAL" "$DAY" "$DAY_COUNT" "$LAST_RESULT" "$LAST_CURE_TS" "$LIGHT_ACTIVE" "$LIGHT_SINCE" "$LIGHT_TOTAL" "$LAST_SUPP" "$LBASE_TS" > "$SE.tmp" && mv "$SE.tmp" "$SE"
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

# 2b. light probe (1 MB, every minute), judged against a baseline of good-state times:
# detect after LNEED consecutive slow samples, clear after LOUT consecutive fast ones; failed (non-200) samples count as neither
lep=$LIGHT_ACTIVE; lfresh=0; lt=0; src=heavy; LL=$ST/light.log; LB=$ST/light-base.log
[ -s "$LB" ] || { [ -s "$LL" ] && awk -v f="$LFLOOR" '$3==200 && $2<f {print $1, $2}' "$LL" > "$LB"; }
lbn=$(cat "$LB" 2>/dev/null | wc -l | tr -d " ")
lbase=$LBDEF
[ "$lbn" -ge "$LBMIN" ] && lbase=$(awk '{print $2}' "$LB" | sort -n | awk '{a[NR]=$1} END{print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}')
lbase=$(awk -v b="$lbase" -v m="$LBMAX" 'BEGIN{print (b>m) ? m : b}')
lthr=$(awk -v b="$lbase" -v k="$LK" -v f="$LFLOOR" 'BEGIN{t=b*k; print (t>f) ? t : f}')
if [ -s "$LL" ] && [ "$LMODE" != off ]; then
  lts=$(tail -n 1 "$LL" | awk '{print $1}'); lt=$(tail -n 1 "$LL" | awk '{print $2}')
  [ $((now - lts)) -lt 600 ] && lfresh=1
  # trailing runs over recent HTTP-200 samples: "<slow_run> <fast_run> <samples>"
  set -- $(awk -v th="$lthr" -v now="$now" -v age="$LAGE" \
    '$3==200 && now-$1<=age {n++; if($2>=th){s++; f=0} else {f++; s=0}} END{print s+0, f+0, n+0}' "$LL")
  lslow=$1; lfast=$2; lnum=$3
  if [ "$lnum" = 0 ]; then lep=0
  elif [ "$LIGHT_ACTIVE" != 1 ] && [ "$lslow" -ge "$LNEED" ]; then lep=1
  elif [ "$LIGHT_ACTIVE" = 1 ] && [ "$lfast" -ge "$LOUT" ]; then lep=0
  fi
  if [ "$lep" = 0 ] && [ "$lts" -gt "$LBASE_TS" ] && [ "$(tail -n 1 "$LL" | awk '{print $3}')" = 200 ] && awk -v t="$lt" -v th="$lthr" 'BEGIN{exit !(t<th)}'; then
    echo "$lts $lt" >> "$LB"; LBASE_TS=$lts
    tail -n "$LBWIN" "$LB" > "$LB.tmp" && mv "$LB.tmp" "$LB"
  fi
else
  lep=0
fi
if [ "$lep" = 1 ] && [ "$LIGHT_ACTIVE" != 1 ]; then
  LIGHT_ACTIVE=1; LIGHT_SINCE=$now; LIGHT_TOTAL=$((LIGHT_TOTAL + 1))
  log "LIGHT episode detected [$LMODE]: last $LNEED 1 MB probes took >= ${lthr}s (baseline ${lbase}s, latest ${lt}s); heavy probe episode=$ep"
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
    if [ "$src" = light ]; then log "EPISODE (light probe): last $LNEED 1 MB probes took >= ${lthr}s (latest ${lt}s), running diag -> $f"
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
  echo "u5g_watchdog_light_baseline_seconds $lbase"
  echo "u5g_watchdog_light_threshold_seconds $lthr"
  echo "u5g_watchdog_light_baseline_samples $lbn"
} > "$OUTP.tmp" && chmod 644 "$OUTP.tmp" && mv "$OUTP.tmp" "$OUTP"
