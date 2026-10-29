#!/bin/bash
# Container start: prepare the /data volume, then hand over to supercronic, which runs the schedule in /app/crontab.
D=${D:-/data}
mkdir -p "$D/textfile" "$D/state" "$D/diag"
[ -f "$D/mode" ] || echo dry > "$D/mode"
[ -f "$D/id_u5g" ] && chmod 600 "$D/id_u5g"
exec supercronic /app/crontab
