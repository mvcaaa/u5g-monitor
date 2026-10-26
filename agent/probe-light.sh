#!/bin/bash
# u5g light probe: ONE small download from DNA per run (default 1 MB), judged by its TIME, not by speed:
# TCP slow start makes the average speed of a 1 MB file misleading (10-26 Mbit/s even in the good state).
# With python3 the download also reads the socket's TCP_INFO: out-of-order data packets received (tcpi_rcv_ooopack) and data segments in.
# Episodes reorder packets (5-16 of the first 100 segments), the good state never does; without python3 curl is used and both are 0.
# Output: $D/textfile/u5g_probe_light.prom (metrics) and $D/state/light.log
# ("<unix_ts> <time_total_s> <http_code> <bytes> <ooo_packets> <data_segs_in>", last 200 lines).
D=${D:-/data}
OUT=$D/textfile/u5g_probe_light.prom
LOGF=$D/state/light.log
SIZE=${LIGHT_SIZE:-1000000}
MAXT=${LIGHT_MAXT:-5}
URL=${LIGHT_URL:-http://nopeus.dna.fi:8080/download?size=$SIZE}
mkdir -p "$D/textfile" "$D/state"
if command -v python3 >/dev/null 2>&1; then
  r=$(python3 -I - "$URL" "$MAXT" 2>/dev/null <<'EOF'
import socket, struct, sys, time, urllib.parse
u, maxt = urllib.parse.urlsplit(sys.argv[1]), float(sys.argv[2])
t0 = time.time(); n = code = ooo = segs = 0; head = b""
try:
    s = socket.create_connection((u.hostname, u.port or 80), timeout=maxt)
    path = u.path + ("?" + u.query if u.query else "")
    s.sendall(f"GET {path} HTTP/1.1\r\nHost: {u.netloc}\r\nUser-Agent: u5g-probe-light\r\nAccept: */*\r\nConnection: close\r\n\r\n".encode())
    while True:
        left = maxt - (time.time() - t0)
        if left <= 0:
            break
        s.settimeout(left)
        b = s.recv(65536)
        if not b:
            break
        if code == 0:  # count body bytes only, like curl's size_download
            head += b
            if b"\r\n\r\n" not in head:
                continue
            h, _, b = head.partition(b"\r\n\r\n")
            code = int(h.split(None, 2)[1])
        n += len(b)
except OSError:
    pass
t = time.time() - t0
try:
    ti = s.getsockopt(socket.IPPROTO_TCP, socket.TCP_INFO, 232)
    segs, = struct.unpack_from("I", ti, 152)
    if len(ti) >= 228:
        ooo, = struct.unpack_from("I", ti, 224)
    s.close()
except (NameError, AttributeError, OSError):
    pass
print(code, n, f"{min(t, maxt):.6f}", ooo, segs)  # like curl -m: a timeout mid-body keeps the http code
EOF
)
else
  r=$(curl -s -L -m "$MAXT" -o /dev/null -w '%{http_code} %{size_download} %{time_total}' "$URL" 2>/dev/null)
fi
set -- $r
code=${1:-0}; bytes=${2:-0}; t=${3:-0}; ooo=${4:-0}; segs=${5:-0}
ts=$(date +%s)
echo "$ts $t $code $bytes $ooo $segs" >> "$LOGF"
tail -n 200 "$LOGF" > "$LOGF.tmp" 2>/dev/null && mv "$LOGF.tmp" "$LOGF"
bps=$(awk -v b="$bytes" -v t="$t" 'BEGIN{printf "%.0f", (t>0) ? b*8/t : 0}')
{
  echo "u5g_probe_light_last_run_timestamp_seconds $ts"
  echo "u5g_probe_light_http_code $code"
  echo "u5g_probe_light_bytes $bytes"
  echo "u5g_probe_light_time_seconds $t"
  echo "u5g_probe_light_download_bits_per_second $bps"
  echo "u5g_probe_light_ooo_packets $ooo"
  echo "u5g_probe_light_data_segs_in $segs"
} > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
