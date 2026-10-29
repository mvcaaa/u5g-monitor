#!/bin/bash
# u5g-watchdog v2: detect "DNA slow" episodes from the light probe (probe-light.sh, 1 MB every minute), run diag, optionally cure the modem.
# Mode file: $D/mode = dry (default: diag only, no cure) | live (diag + cure)
D=${D:-/data}
OUTP=$D/textfile/u5g_watchdog.prom
ST=$D/state; SE=$ST/state.env; LOG=$D/watchdog.log
mkdir -p "$ST" "$D/diag"
MODE=$(cat "$D/mode" 2>/dev/null || echo dry)
MININT=${MININT:-3600}      # min seconds between triggers (episodes so far were >= 4.4 h apart; a failed cure is retried after 1 h)
MAXDAY=${MAXDAY:-0}         # max triggers per day, 0 = no limit (MININT alone prevents cure loops)
WAITAFTER=${WAITAFTER:-170} # seconds to wait after cure before re-measuring (the modem cycle itself holds 0D for 120 s, see docs/KNOWN_GAPS.md)
SSHC=${SSHC:-"ssh -p ${MODEM_SSH_PORT:-2222} -i $D/id_u5g -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new ${MODEM_USER:-admin}@${MODEM_HOST:?set MODEM_HOST}"}
PROBE=${PROBE:-$D/probe-light.sh}
EPTEST=${EPTEST:-off}       # episode tests before the cure (~21 MB, 2-7 min): a path to episode-tests.sh enables them; off since 2026-10-28
LNEED=${LNEED:-3}           # consecutive slow samples (1 per minute) to detect
LOUT=${LOUT:-5}             # consecutive fast samples to clear
LOOO=${LOOO:-100}           # fast detection: ONE sample of >= LOOOT s with >= LOOO out-of-order packets (light.log column 5) starts an episode; 0 = off
LOOOT=${LOOOT:-3}           # fast detection: minimum time (s); episodes 4-5 s with 140-330 packets, false slow samples <= 1.7 s with up to 110
CONFMB=${CONFMB:-10}        # cure only if the diag's 10 MB DNA download is below this (Mbit/s); episodes 1.3-1.6, good state >= 20; 0 = no check
LOOOSH=${LOOOSH:-2}         # with LOOO=0: log such samples as "SHADOW" only, to evaluate the fast rule
LK=${LK:-2}                 # slow = time >= max(LK x baseline, LFLOOR); 2 x ~0.47 s catches ~10 Mbit/s and below
LFLOOR=${LFLOOR:-0.8}       # threshold floor (s); good state p50 0.47 s / p98 1.07 s, severe episode 3.5-5 s (capped by LIGHT_MAXT)
LBMIN=${LBMIN:-30}          # baseline: samples needed before it replaces LBDEF
LBDEF=${LBDEF:-0.5}         # baseline: default (s)
LBMAX=${LBMAX:-1.2}         # baseline: clamp, so a drifting baseline cannot push the threshold towards the 5 s probe timeout
LBWIN=${LBWIN:-1440}        # baseline: last N fast samples taken outside episodes (~24 h)
LAGE=${LAGE:-400}           # samples older than this (s) are ignored

exec 9>"$ST/lock"; flock -n 9 || exit 0
log() { echo "$(date '+%F %T') [$MODE] $*" >> "$LOG"; }
now=$(date +%s)

LAST_TRIGGER=0; CURES_TOTAL=0; DRY_TOTAL=0; DAY=$(date +%F); DAY_COUNT=0; LAST_RESULT=-1; LAST_CURE_TS=0
LIGHT_ACTIVE=0; LIGHT_SINCE=0; LIGHT_TOTAL=0; LAST_SUPP=0; LBASE_TS=0; LAST_SHADOW=0; UNCONF_TOTAL=0; CONF_TOTAL=0
[ -f "$SE" ] && . "$SE"
save() {
  printf 'LAST_TRIGGER=%s\nCURES_TOTAL=%s\nDRY_TOTAL=%s\nDAY=%s\nDAY_COUNT=%s\nLAST_RESULT=%s\nLAST_CURE_TS=%s\nLIGHT_ACTIVE=%s\nLIGHT_SINCE=%s\nLIGHT_TOTAL=%s\nLAST_SUPP=%s\nLBASE_TS=%s\nLAST_SHADOW=%s\nUNCONF_TOTAL=%s\nCONF_TOTAL=%s\n' \
    "$LAST_TRIGGER" "$CURES_TOTAL" "$DRY_TOTAL" "$DAY" "$DAY_COUNT" "$LAST_RESULT" "$LAST_CURE_TS" "$LIGHT_ACTIVE" "$LIGHT_SINCE" "$LIGHT_TOTAL" "$LAST_SUPP" "$LBASE_TS" "$LAST_SHADOW" "$UNCONF_TOTAL" "$CONF_TOTAL" > "$SE.tmp" && mv "$SE.tmp" "$SE"
}

[ "$DAY" != "$(date +%F)" ] && { DAY=$(date +%F); DAY_COUNT=0; }

# 1. baseline and threshold: median of good-state times, learned only outside episodes
LL=$ST/light.log; LB=$ST/light-base.log
[ -s "$LB" ] || { [ -s "$LL" ] && awk -v f="$LFLOOR" '$3==200 && $2<f {print $1, $2}' "$LL" > "$LB"; }
lbn=$(cat "$LB" 2>/dev/null | wc -l | tr -d " ")
lbase=$LBDEF
[ "$lbn" -ge "$LBMIN" ] && lbase=$(awk '{print $2}' "$LB" | sort -n | awk '{a[NR]=$1} END{print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}')
lbase=$(awk -v b="$lbase" -v m="$LBMAX" 'BEGIN{print (b>m) ? m : b}')
lthr=$(awk -v b="$lbase" -v k="$LK" -v f="$LFLOOR" 'BEGIN{t=b*k; print (t>f) ? t : f}')

# 2. episode state: detect after LNEED consecutive slow samples, clear after LOUT consecutive fast ones;
#    failed (non-200) samples count as neither
ep=$LIGHT_ACTIVE; fresh=0; lt=0; reach=-1
if [ -s "$LL" ]; then
  lts=$(tail -n 1 "$LL" | awk '{print $1}'); lt=$(tail -n 1 "$LL" | awk '{print $2}')
  [ $((now - lts)) -lt 600 ] && fresh=1
  # trailing runs over recent HTTP-200 samples: "<slow_run> <fast_run> <samples> <out-of-order packets of the newest one>"
  set -- $(awk -v th="$lthr" -v now="$now" -v age="$LAGE" \
    '$3==200 && now-$1<=age {n++; o=$5+0; lt2=$2; if($2>=th){s++; f=0} else {f++; s=0}} END{print s+0, f+0, n+0, o+0, lt2+0}' "$LL")
  lslow=$1; lfast=$2; lnum=$3; looo=$4; lt200=$5; lwhy="last $LNEED 1 MB probes took >= ${lthr}s"
  if [ "$LIGHT_ACTIVE" != 1 ] && [ "$lslow" -ge 1 ] && [ "$looo" -ge "$LOOOSH" ] && [ "$LOOO" = 0 ] && [ "$lts" -gt "${LAST_SHADOW:-0}" ]; then
    LAST_SHADOW=$lts; log "SHADOW: slow 1 MB probe ${lt}s with $looo out-of-order packets (slow run $lslow)"
  fi
  if [ "$lnum" = 0 ]; then ep=0
  elif [ "$LIGHT_ACTIVE" != 1 ] && [ "$lslow" -ge "$LNEED" ]; then ep=1
  elif [ "$LIGHT_ACTIVE" != 1 ] && [ "$LOOO" -gt 0 ] && [ "$lslow" -ge 1 ] && [ "$looo" -ge "$LOOO" ] && awk -v t="$lt200" -v m="$LOOOT" 'BEGIN{exit !(t>=m)}'; then
    ep=1; lwhy="1 MB probe took ${lt200}s (>= ${LOOOT}s) with $looo out-of-order packets (>= $LOOO)"
  elif [ "$LIGHT_ACTIVE" = 1 ] && [ "$lfast" -ge "$LOUT" ]; then ep=0
  fi
  if [ "$ep" = 0 ] && [ "$lts" -gt "$LBASE_TS" ] && [ "$(tail -n 1 "$LL" | awk '{print $3}')" = 200 ] && awk -v t="$lt" -v th="$lthr" 'BEGIN{exit !(t<th)}'; then
    echo "$lts $lt" >> "$LB"; LBASE_TS=$lts
    tail -n "$LBWIN" "$LB" > "$LB.tmp" && mv "$LB.tmp" "$LB"
  fi
else
  ep=0
fi
if [ "$ep" = 1 ] && [ "$LIGHT_ACTIVE" != 1 ]; then
  LIGHT_ACTIVE=1; LIGHT_SINCE=$now; LIGHT_TOTAL=$((LIGHT_TOTAL + 1))
  log "EPISODE started: $lwhy (baseline ${lbase}s, latest ${lt}s)"
elif [ "$ep" = 0 ] && [ "$LIGHT_ACTIVE" = 1 ]; then
  LIGHT_ACTIVE=0
  log "EPISODE cleared after $((now - LIGHT_SINCE))s"
fi

# 3. trigger
if [ "$ep" = 1 ] && [ $((now - LAST_TRIGGER)) -ge "$MININT" ] && { [ "$MAXDAY" = 0 ] || [ "$DAY_COUNT" -lt "$MAXDAY" ]; }; then
  if $SSHC ping 2>/dev/null | grep -q pong; then
    reach=1
    LAST_TRIGGER=$now; DAY_COUNT=$((DAY_COUNT + 1))
    f="$D/diag/episode-$(date +%Y%m%d-%H%M).txt"
    log "EPISODE: running diag -> $f"
    timeout 220 $SSHC diag > "$f" 2>&1
    if [ "$EPTEST" != off ] && [ -f "$EPTEST" ]; then
      log "EPISODE: running tests -> ${f%.txt}-tests.txt"
      D="$D" EPT_KIND=episode EPT_STEM="${f%.txt}" timeout 420 bash "$EPTEST" > "${f%.txt}-tests.txt" 2>&1
    fi
    # the diag's own DNA download confirms the episode; a failed or missing download does not block the cure
    dmb=$(awk '/nopeus\.dna\.fi.*B\/s code=200/ {for(i=1;i<=NF;i++) if($(i+1)=="B/s") printf "%.1f", $i*8/1e6}' "$f" 2>/dev/null)
    if [ -n "$dmb" ] && [ "$CONFMB" != 0 ] && awk -v m="$dmb" -v c="$CONFMB" 'BEGIN{exit !(m>=c)}'; then
      conf=0; UNCONF_TOTAL=$((UNCONF_TOTAL + 1))
      log "NOT CONFIRMED: diag downloads ${dmb} Mbit/s from DNA (>= ${CONFMB}), no cure"
    else
      conf=1; CONF_TOTAL=$((CONF_TOTAL + 1))
      if [ -n "$dmb" ]; then log "CONFIRMED: diag downloads ${dmb} Mbit/s from DNA (< ${CONFMB})"; else log "CONFIRMED: no DNA result in the diag, treated as confirmed"; fi
    fi
    if [ "$conf" = 1 ] && [ "$MODE" = live ]; then
      CURES_TOTAL=$((CURES_TOTAL + 1)); LAST_CURE_TS=$(date +%s)
      log "CURE: sending cure, waiting ${WAITAFTER}s"
      $SSHC cure >> "$LOG" 2>&1
      sleep "$WAITAFTER"
      D="$D" "$PROBE" >/dev/null 2>&1
      set -- $(tail -n 1 "$LL" 2>/dev/null)
      if [ "${3:-0}" = 200 ] && awk -v t="${2:-99}" -v th="$lthr" 'BEGIN{exit !(t<th)}'; then LAST_RESULT=1; else LAST_RESULT=0; fi
      log "CURE result=$LAST_RESULT 1 MB in ${2:-?}s (threshold ${lthr}s) code=${3:-?}"
      log "CURE: running diag after the cure -> ${f%.txt}-after.txt"
      timeout 220 $SSHC diag > "${f%.txt}-after.txt" 2>&1
    elif [ "$conf" = 1 ]; then
      DRY_TOTAL=$((DRY_TOTAL + 1))
      log "DRY-RUN: would cure now (no action taken)"
    fi
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
  echo "u5g_watchdog_unconfirmed_total $UNCONF_TOTAL"
  echo "u5g_watchdog_confirmed_total $CONF_TOTAL"
  echo "u5g_watchdog_last_cure_result $LAST_RESULT"
  echo "u5g_watchdog_last_cure_timestamp_seconds $LAST_CURE_TS"
  echo "u5g_watchdog_triggers_today $DAY_COUNT"
  echo "u5g_watchdog_detections_total $LIGHT_TOTAL"
  echo "u5g_watchdog_light_baseline_seconds $lbase"
  echo "u5g_watchdog_light_threshold_seconds $lthr"
  echo "u5g_watchdog_light_baseline_samples $lbn"
} > "$OUTP.tmp" && chmod 644 "$OUTP.tmp" && mv "$OUTP.tmp" "$OUTP"
