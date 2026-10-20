# Experiment: turning the modem's antenna towards the serving site

Why and what is expected: [FINDINGS.md](../FINDINGS.md), sections "Antenna orientation" and the M1-XS refinement with its
**pre-registered prediction** (written before the turn; do not edit it afterwards, add results below instead).

In short: the antenna faces west (~265°) at a farther site that probably serves the NR n28 leg, while the LTE anchor comes from a nearer
site SSE (~150°) about 115° off the antenna's axis. Turning the antenna moves its gain from one site to the other, so LTE and NR signal
levels should move in **opposite** directions if they come from different sites (M1-XS), and **together** if they come from the same one.

## Needs
- A dry roof (the owner turns the antenna by hand; no tools on the modem side).
- An Android phone with a DNA SIM and **NetMonster** (5G enabled in the phone's network settings, **Wi-Fi off** on the roof so that the
  phone uses its own mobile connection), and a compass (any app, or Google Maps).
- At least ~1 h of radio data in the current position before the turn (`agent/radio-status.sh`, every 5 min).

## Steps
1. **Watchdog to `dry`** so that an episode or a short signal drop during the turn does not start a cure and mix up the data:
   layout B `echo dry | sudo tee /mnt/Main/u5g-watchdog/mode`, compose `echo dry > data/mode`. Note the time.
2. **Measure the current azimuth** of the modem with the compass (phone held flat along the modem's front). Note it.
3. **Phone readings in the current position** (NetMonster, start a speed test or a video so that the 5G leg is attached, read during the
   transfer): LTE serving cell (site id, PCI, band, RSRP, SINR), the NR leg (PCI, ARFCN, RSRP, SINR) if shown, neighbour cells.
   Screenshot. Optional: turn slowly through 360° holding the phone in front of you; the body shadows the signal from behind, so the
   serving site's RSRP is highest when you face it (direction to within ~30°).
4. **Position 1, ~205°** (between the two sites). Note the exact time when it is fixed. Leave it for **30-40 min** (6-8 radio snapshots).
   Phone readings as in step 3.
5. **Position 2, ~150°** (towards the SSE serving site). Note the time; 30-40 min; phone readings.
6. Choose the final position from the numbers (step "Evaluate"), set it, note the time.
7. **Watchdog back to `live`** (if it was live before): `echo live | sudo tee /mnt/Main/u5g-watchdog/mode`. Check that the dashboard's
   "Mode" shows LIVE and "Modem ssh" ok.
8. Put each time on the dashboard as an annotation tagged `note` (Ctrl/Cmd+click on a graph), e.g. "antenna 205°".

## Evaluate
```bash
PROM=http://<prometheus> python3 scripts/compare-windows.py \
  "265=<before start>/<before end>" "205=<pos1 start+5min>/<pos1 end>" "150=<pos2 start+5min>/<pos2 end>"
```
It prints the mean of LTE/NR RSRP, SINR, RSRQ, Tx power (modem GSTATUS every 5 min and UniFi every minute), the light probe and the
5 MB probes per window, and the carriers seen. Rules:
- Compare only windows with the **same carriers** (LTE EARFCN and NR ARFCN); a carrier change invalidates the comparison for that leg.
- Skip the first ~5 min after each turn (the modem may re-select cells).
- The prediction table in FINDINGS decides: LTE up and NR down (or NR gone) = different sites; both up by a similar amount (within ~3 dB) = same site.
- Speed: also look at the next good-state reference test (04:10 / 16:10) and the day's light-probe median.

## Follow-up on another day: NNW position (~345°)
A separate test, not part of the first session; run it on another day once the new position has been observed for a while (e.g. a few days
with or without episodes). Target: a farther site (~2-2.5 km, estimate) that CellMapper lists with LTE B3/B7/B8 and NR n1 + n28 on the same
mast (CellMapper has no sector data for it, which says little). If the modem anchors LTE there, its NR leg most likely comes from the same
site (co-located EN-DC) - the cleanest test of M1-XS if episodes then stop - and it could add B7. Risks: a much weaker signal than the near
sites, co-channel interference from the near SSE site behind the antenna, and the network may keep the modem on the near site anyway.
Same procedure (dry mode, azimuth, phone readings, 30-40 min or longer, back to live); note the LTE site/PCI and NR ARFCN the modem gets
(`u5g_radio_info`) and compare with `compare-windows.py`.

## Results
(fill in after the experiment: azimuths and times, the compare-windows table, phone screenshots summary, conclusion for M1-XS, final position)
