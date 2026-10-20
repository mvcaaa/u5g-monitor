#!/bin/bash
# u5g-radio-status: every 5 min, read-only radio snapshot from the modem (dispatcher command "radio-status", no traffic).
# Raw output is appended to $D/radio/<YYYYMMDD>.txt; the main GSTATUS fields go to $D/textfile/u5g_radio.prom (atomic).
D=${D:-/data}
SSHC=${SSHC:-"ssh -p ${MODEM_SSH_PORT:-2222} -i $D/id_u5g -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new ${MODEM_USER:-admin}@${MODEM_HOST:?set MODEM_HOST}"}
OUT=$D/textfile/u5g_radio.prom
mkdir -p "$D/radio" "$D/textfile"
r=$(timeout 60 $SSHC radio-status 2>&1)
printf '%s\n' "$r" >> "$D/radio/$(date +%Y%m%d).txt"
ok=0; echo "$r" | grep -q '^### done' && echo "$r" | grep -q '^!GSTATUS:' && ok=1

# GSTATUS lines hold up to two tab-separated "key: value" pairs; NR keys carry an SCCn prefix that depends on the carrier layout
echo "$r" | sed -n '/^### GSTATUS/,/^### LTEINFO/p' | awk -F'\t' -v ok="$ok" -v now="$(date +%s)" '
function num(v) { return (v ~ /^-?[0-9.]+$/) ? v : "" }
function out(name, v) { if (v != "") printf "u5g_radio_%s %s\n", name, v }
{ for (i = 1; i <= NF; i++) { p = index($i, ":"); if (!p) continue
    k = substr($i, 1, p - 1); v = substr($i, p + 1); gsub(/^ +| +$/, "", k); gsub(/^ +| +$/, "", v); sub(/^SCC[0-9] /, "", k); kv[k] = v } }
END {
  split(kv["Cell ID"], c, " "); gsub(/[()]/, "", c[2]); split(kv["TAC"], t, " ")
  if (ok)
  printf "u5g_radio_info{system_mode=\"%s\",lte_band=\"%s\",lte_rx_chan=\"%s\",nr_band=\"%s\",nr_rx_chan=\"%s\",cell_id=\"%s\",tac=\"%s\",rrc=\"%s\"} 1\n",
    kv["System mode"], kv["LTE band"], kv["LTE Rx chan"], kv["NR5G band"], kv["NR5G Rx chan"], c[2], t[1], kv["RRC state"]
  out("rrc_connected", (kv["RRC state"] ~ /Connected/) ? 1 : (kv["RRC state"] == "" ? "" : 0))
  out("endc", (kv["System mode"] == "ENDC") ? 1 : (kv["System mode"] == "" ? "" : 0))
  out("temperature_celsius", num(kv["Temperature"])); out("reset_counter", num(kv["Reset Counter"]))
  out("lte_tx_power_dbm", num(kv["PCC Tx Power"])); out("lte_sinr_db", num(kv["SINR (dB)"])); out("lte_rsrq_db", num(kv["RSRQ (dB)"]))
  for (a = 0; a < 4; a++) { v = num(kv["PCC Rx" a " RSRP"]); if (v != "") printf "u5g_radio_lte_rsrp_dbm{rx=\"%d\"} %s\n", a, v }
  out("nr_tx_power_dbm", num(kv["NR5G Tx Power"])); out("nr_sinr_db", num(kv["NR5G SINR (dB)"]))
  out("nr_rsrp_dbm", num(kv["NR5G RSRP (dBm)"])); out("nr_rsrq_db", num(kv["NR5G RSRQ (dB)"]))
  printf "u5g_radio_ok %d\nu5g_radio_last_run_timestamp_seconds %d\n", ok, now
}' > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
