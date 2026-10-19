#!/bin/sh
# Creates the CUSTOM band profile 0D "No n28 Test" on the modem. WRITES to the modem's band-profile table:
# run it only by hand, on the owner's explicit decision, never from automation. Does not change the active profile.
# Usage on a workstation:  ssh <ssh_user>@<modem_ip> 'sh -s' < modem/create-profile-0d.sh
# Syntax (verified from the owner's shell history, 2026-10-19; Sierra EM9 AT reference: AT!BAND=<Index>,<Operation 1=add>,"<Name>",<RAT>,<masks>):
#   RAT 0 = GSM/WCDMA (GW), 1 = LTE, 3 = NR NSA, 4 = NR SA.   0D = profile 00 ("All bands") with n28 cleared in NR NSA.
AT() { uiwwand-chat -t 5 "$1" 2>&1; }
NAME="No n28 Test"
EXPECTED='0 - GW: 100200000EC00000
1 - LTE: 0000A7E2BB0F38DF 0000000000000042
3 - NRNSA: 000081A0330A38D7 0000000000007C62
4 - NRSA: 000081A03B0A38D7 0000000000007C62'
shown() { AT 'AT!BAND?0D' | grep -E '^[0134] - ' | tr -s ' '; }

if AT 'AT!BAND=?' | grep -q '^0D,'; then
  echo "profile 0D already exists - NOT overwriting. Current definition:"; AT 'AT!BAND?0D'
  [ "$(shown)" = "$EXPECTED" ] && echo "MATCHES the expected definition" || { echo "DIFFERS from the expected definition (see docs/baselines/band-profiles.txt)"; exit 2; }
  exit 0
fi
echo "creating profile 0D ..."
AT "AT!BAND=0D,1,\"$NAME\",1,0000A7E2BB0F38DF,0000000000000042"
AT "AT!BAND=0D,1,\"$NAME\",3,000081A0330A38D7,0000000000007C62"
AT "AT!BAND=0D,1,\"$NAME\",0,100200000EC00000"
AT "AT!BAND=0D,1,\"$NAME\",4,000081A03B0A38D7,0000000000007C62"
echo "result:"; AT 'AT!BAND?0D'
if [ "$(shown)" = "$EXPECTED" ]; then echo "VERIFIED: 0D matches the expected definition. Active profile unchanged: $(AT 'AT!BAND?' | sed -n 2p)"
else echo "MISMATCH after creation - inspect with AT!BAND? and AT!BAND=? ; do not run the cure"; exit 2; fi
