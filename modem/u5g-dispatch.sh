#!/bin/sh
# u5g-dispatch: forced command for the TrueNAS watchdog key. Allowed: ping | diag | cure
CMD="$SSH_ORIGINAL_COMMAND"
AT() { uiwwand-chat -t 5 "$1" 2>&1; }
NS() { awk -v f="$2" -v k="$3" '$1==(f":"){if(!h){for(i=2;i<=NF;i++)n[i]=$i;h=1}else{for(i=2;i<=NF;i++)if(n[i]==k){print $i;exit}}}' "$1"; }
cnt() { echo "$(NS /proc/net/snmp Tcp InSegs) $(NS /proc/net/snmp Tcp RetransSegs) $(NS /proc/net/netstat TcpExt TCPOFOQueue) $(NS /proc/net/netstat TcpExt TCPDSACKOldSent)"; }
case "$CMD" in
  ping)
    echo pong
    ;;
  diag)
    echo "### diag $(date '+%F %T') uptime: $(cut -d' ' -f1 /proc/uptime)s"
    echo "### BAND profile (current / defined)"; AT 'AT!BAND?' | head -1; AT 'AT!BAND=?' | sed '/^Available:/,$d' | grep -E '^[0-9A-F]{2},'
    echo "### GSTATUS"; AT 'AT!GSTATUS?'
    C0=$(cnt)
    echo "### ping nopeus.dna.fi 56B"; ping -c 5 -W 2 -q nopeus.dna.fi 2>&1 | tail -2
    echo "### ping nopeus.dna.fi 1400B"; ping -c 5 -W 2 -s 1400 -q nopeus.dna.fi 2>&1 | tail -2
    echo "### ping 1.1.1.1 56B"; ping -c 5 -W 2 -q 1.1.1.1 2>&1 | tail -2
    echo "### download (10 MB each)"
    for u in "http://nopeus.dna.fi:8080/download?size=10000000" "https://speed.cloudflare.com/__down?bytes=10000000"; do
      echo "$u $(curl -s -m 25 -o /dev/null -w '%{speed_download} B/s code=%{http_code}' "$u")"
    done
    C1=$(cnt)
    echo "### TCP delta (InSegs Retrans OFO DSACK): $C0 -> $C1"
    set -- $C0 $C1; echo "delta insegs=$(($5-$1)) retrans=$(($6-$2)) ofo=$(($7-$3)) dsack=$(($8-$4))"
    if command -v traceroute >/dev/null 2>&1; then
      echo "### traceroute nopeus.dna.fi"; traceroute -n -m 12 -w 2 nopeus.dna.fi 2>&1
    fi
    echo "### done"
    ;;
  cure)
    if ! AT 'AT!BAND=?' | grep -q '^0D,'; then
      echo "custom band profile 0D is not defined on this modem; cure refused" >&2; exit 3
    fi
    if [ -f /etc/persistent/band-cycle.sh ]; then
      nohup sh /etc/persistent/band-cycle.sh >/dev/null 2>&1 &
      echo "cure started $(date '+%F %T')"
    else
      echo "band-cycle.sh missing" >&2; exit 2
    fi
    ;;
  *)
    echo "denied" >&2; exit 1
    ;;
esac
