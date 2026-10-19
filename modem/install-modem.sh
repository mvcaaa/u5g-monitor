#!/bin/bash
# Run from a workstation that already has admin ssh access to the modem. Installs the dispatcher, band-cycle.sh and the
# restricted watchdog key, and starts the dedicated dropbear on port 2222. NOTHING is written to flash (see docs/MODEM.md).
# usage: modem/install-modem.sh <admin_user@modem_ip> [admin_ssh_port]
set -e
TARGET=${1:?usage: $0 user@modem_ip [port]}; PORT=${2:-22}
HERE=$(cd "$(dirname "$0")" && pwd); PUB=$HERE/../data/id_u5g.pub
[ -f "$PUB" ] || { echo "run scripts/init.sh first (generates data/id_u5g)"; exit 1; }
SSH="ssh -p $PORT $TARGET"
$SSH 'cat > /etc/persistent/u5g-dispatch.sh && chmod 755 /etc/persistent/u5g-dispatch.sh' < "$HERE/u5g-dispatch.sh"
if $SSH 'test -f /etc/persistent/band-cycle.sh'; then
  echo "band-cycle.sh already on the modem - leaving the live copy untouched"
else
  $SSH 'cat > /etc/persistent/band-cycle.sh && chmod 755 /etc/persistent/band-cycle.sh' < "$HERE/band-cycle.sh"
fi
KEY=$(cut -d' ' -f1,2 "$PUB")
LINE="command=\"/etc/persistent/u5g-dispatch.sh\",no-pty,no-port-forwarding,no-agent-forwarding $KEY u5g-watchdog"
# append only if this key is not there yet (compare on the key material)
$SSH "grep -qF '$(cut -d' ' -f2 "$PUB")' /etc/persistent/.ssh/authorized_keys || printf '%s\n' '$LINE' >> /etc/persistent/.ssh/authorized_keys"
# dedicated dropbear: key auth from /etc/persistent/.ssh (the stock dropbear on :22 does not read it)
$SSH "ps w | grep -q '[-]p 2222' || dropbear -r /var/run/dropbear_ed25519_host_key -p 2222 -l br0 -D /etc/persistent/.ssh -E"
echo "installed. test:  ssh -p 2222 -i data/id_u5g -o BatchMode=yes ${TARGET#*@} ping   (expect: pong)"
