# Experiment: a second DNA subscription in the modem's second SIM slot

Question: are the episodes tied to **this subscription** (its profile, QoS/charging policy or session), or to the modem and the radio
network around it? The modem, antenna, sites and monitoring stay the same; only the subscriber changes. Pre-registered prediction:
[FINDINGS.md](../FINDINGS.md), section "Second-SIM test". Do not edit it afterwards; add results below.

The second SIM is a DNA prepaid data subscription (unlimited data, ~300 Mbit/s class), normally used in the Android phone for NetMonster.
The U5G has two SIM slots used as primary/backup (one radio module: one SIM active at a time; no aggregation of both subscriptions).

## Steps
1. **Watchdog to `dry`** (the modem goes offline while the unit is open): layout B `echo dry | sudo tee /mnt/Main/u5g-watchdog/mode`.
2. On the roof: insert the prepaid SIM into **slot 2**; leave the contract SIM in slot 1. Close the unit.
3. If the modem rebooted (uptime in `diag` / UniFi): re-install the modem side with `modem/install-modem.sh` (docs/OPERATIONS.md
   "After a modem restart"), check `ping` -> `pong`, that `0D` exists and `AT!BAND?` is `00`.
4. Watchdog back to `live` (the cure works with either SIM).
5. Switch the active SIM to slot 2 in the UniFi UI. **Note the exact time** (each switch is a new attach, which matters for the
   prediction). Check the public IP / operator in UniFi and that the light probe is fast.
6. Stay on slot 2 for **1-2 days** (4-8 expected onsets). Then switch back to slot 1 and note the time. Repeat later if useful.
7. Every switch time goes onto the dashboard as a `note` annotation.

## What to look at
- Onsets of light-probe episodes (`u5g_watchdog_detections_total`, the 1 MB probe) against both grids: the old one (2026-10-23 01:33,
  07:37, 13:41, 19:45, +6 h 04 min each) and "switch time + n x 6 h 04 min".
- Whether the radio is the same (`u5g_radio_info`: same LTE/NR carriers and cells as with the contract SIM).
- Speed in the good state (reference tests 04:10 / 16:10, light-probe median): the prepaid profile may differ.

## Results
(fill in: switch times, onsets observed with each SIM, which grid they follow, conclusion)
