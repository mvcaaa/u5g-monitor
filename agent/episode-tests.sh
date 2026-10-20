#!/bin/bash
# u5g-episode-tests: discrimination tests run by the watchdog once per triggered episode (before any cure); can also be run by hand.
# 1. 100 DF pings per size (56..1472 B) to DNA and Cloudflare in parallel: does loss depend on packet size (MTU/fragment path)?
# 2. 5 MB DNA downloads with the default MSS, 1200, 1000 and the default again: does a smaller segment size restore speed?
# Human-readable report on stdout; metrics to $D/textfile/u5g_eptest.prom (atomic). About 21 MB of traffic, 2-6 min.
D=${D:-/data}
OUT=$D/textfile/u5g_eptest.prom
DNA_HOST=${DNA_HOST:-nopeus.dna.fi}
CF_HOST=${CF_HOST:-speed.cloudflare.com}
SIZES=${EPT_SIZES:-56 1000 1200 1400 1472}
COUNT=${EPT_COUNT:-100}
MSSL=${EPT_MSS:-0 1200 1000 0}   # 0 = default MSS
DLSIZE=${EPT_DLSIZE:-5000000}
DLMAXT=${EPT_DLMAXT:-60}
mkdir -p "$D/textfile"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
t0=$(date +%s)
echo "episode tests start $(date '+%F %T %Z')"

pingset() { # name host
  for s in $SIZES; do
    r=$(ping -M do -c "$COUNT" -i 0.2 -W 2 -q -s "$s" "$2" 2>&1)
    echo "$2 size=$s $(echo "$r" | grep -E 'packet loss|rtt' | tr '\n' ' ')" >> "$T/$1.txt"
    echo "$r" | awk -F', ' -v t="$1" -v s="$s" '/packet loss/{sub(/%.*/,"",$3); printf "u5g_eptest_ping_loss_ratio{target=\"%s\",size=\"%s\"} %.4f\n", t, s, $3/100}' >> "$T/$1.prom"
    echo "$r" | awk -F'[/ =]+' -v t="$1" -v s="$s" '/^rtt/{printf "u5g_eptest_ping_rtt_avg_seconds{target=\"%s\",size=\"%s\"} %.6f\n", t, s, $7/1000}' >> "$T/$1.prom"
  done
}
pingset dna "$DNA_HOST" &
pingset cloudflare "$CF_HOST" &
wait
cat "$T/dna.txt" "$T/cloudflare.txt" 2>/dev/null

# Downloads: python sets TCP_MAXSEG before connect and reads TCP_INFO (rcv_mss, advmss, rtt) afterwards; Linux only.
python3 -I - "$DNA_HOST" "$DLSIZE" "$DLMAXT" $MSSL > "$T/dl.txt" 2>&1 <<'EOF'
import socket, struct, sys, time
host, size, maxt = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
for run, mss in enumerate((int(m) for m in sys.argv[4:]), 1):
    lab = mss or "default"
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if mss:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_MAXSEG, mss)
    s.settimeout(min(30, maxt))
    t0 = time.time(); n = 0; rcv = adv = rtt = code = 0; head = b""
    try:
        s.connect((host, 8080))
        s.sendall(f"GET /download?size={size} HTTP/1.1\r\nHost: {host}:8080\r\nUser-Agent: u5g-eptest\r\nAccept: */*\r\nConnection: close\r\n\r\n".encode())
        while time.time() - t0 < maxt:
            b = s.recv(65536)
            if not b:
                break
            if code == 0:  # the server answers 500 without a User-Agent: count body bytes only, keep the status
                head += b
                if b"\r\n\r\n" not in head:
                    continue
                h, _, b = head.partition(b"\r\n\r\n")
                code = int(h.split(None, 2)[1])
            n += len(b)
        ti = s.getsockopt(socket.IPPROTO_TCP, socket.TCP_INFO, 104)
        rcv, = struct.unpack_from("I", ti, 20); rtt, = struct.unpack_from("I", ti, 68); adv, = struct.unpack_from("I", ti, 84)
    except OSError as e:
        print(f"# run={run} mss={lab} error: {e}")
    s.close()
    dt = max(time.time() - t0, 0.001)
    print(f"# run={run} mss={lab} bytes={n} secs={dt:.1f} mbps={n*8/dt/1e6:.2f} code={code} rcv_mss={rcv} advmss={adv} rtt_ms={rtt/1000:.0f}")
    l = f'run="{run}",mss="{lab}"'
    print(f"u5g_eptest_download_bits_per_second{{{l}}} {n*8/dt:.0f}")
    print(f"u5g_eptest_download_bytes{{{l}}} {n}")
    print(f"u5g_eptest_download_http_code{{{l}}} {code}")
    print(f"u5g_eptest_download_rcv_mss_bytes{{{l}}} {rcv}")
EOF
grep '^#' "$T/dl.txt" | sed 's/^# //'

{
  cat "$T/dna.prom" "$T/cloudflare.prom" 2>/dev/null
  grep '^u5g_' "$T/dl.txt"
  echo "u5g_eptest_duration_seconds $(( $(date +%s) - t0 ))"
  echo "u5g_eptest_last_run_timestamp_seconds $(date +%s)"
} > "$OUT.tmp" && chmod 644 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
echo "episode tests end $(date '+%F %T %Z')"
