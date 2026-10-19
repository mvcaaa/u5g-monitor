#!/bin/sh
# Read-only: TCP receiver counters per destination (DNA vs Cloudflare), one download at a time. Run as admin: ssh user@modem 'sh -s' < ofo-test.sh
NS() { awk -v f="$2" -v k="$3" '$1==(f":"){if(!h){for(i=2;i<=NF;i++)n[i]=$i;h=1}else{for(i=2;i<=NF;i++)if(n[i]==k){print $i;exit}}}' "$1"; }
cnt() { echo "$(NS /proc/net/snmp Tcp InSegs) $(NS /proc/net/snmp Tcp RetransSegs) $(NS /proc/net/netstat TcpExt TCPOFOQueue) $(NS /proc/net/netstat TcpExt TCPDSACKOldSent)"; }
echo "### ofo-test $(date '+%F %T')"
for u in "http://nopeus.dna.fi:8080/download?size=5000000" "https://speed.cloudflare.com/__down?bytes=5000000" "http://nopeus.dna.fi:8080/download?size=5000000"; do
  C0=$(cnt); R=$(curl -s -m 20 -o /dev/null -w '%{speed_download} B/s code=%{http_code}' "$u"); C1=$(cnt)
  set -- $C0 $C1
  echo "$u | $R | insegs=$(($5-$1)) retrans=$(($6-$2)) ofo=$(($7-$3)) dsack=$(($8-$4))"
  sleep 3
done
echo "### done"
