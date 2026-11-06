#!/bin/bash
# Container start: prepare the /data volume, then hand over to supercronic, which runs the schedule in /app/crontab
# (/app/crontab.watch when data/mode is "watch"; a mode change takes effect at the next container start).
D=${D:-/data}
mkdir -p "$D/textfile" "$D/state" "$D/diag"
[ -f "$D/mode" ] || echo dry > "$D/mode"
[ -f "$D/id_u5g" ] && chmod 600 "$D/id_u5g"
CRONTAB=/app/crontab; [ "$(cat "$D/mode" 2>/dev/null)" = watch ] && CRONTAB=/app/crontab.watch
echo "init: mode $(cat "$D/mode"), schedule $CRONTAB"
exec supercronic "$CRONTAB"
