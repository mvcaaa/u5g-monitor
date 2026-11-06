# Final report: the U5G slow episodes, October-November 2026

Status 2026-11-06. The lab is being wound down: the episodes stopped by themselves, most likely on the operator's side. This report sums up
what was observed, what helped, what is still unproven and how to bring the lab back. Evidence and details: [FINDINGS.md](FINDINGS.md),
the day reports in [episodes/](episodes/). Times are local (Europe/Helsinki).

## In short
- From ~7-9 Oct (after DNA's maintenance on 6 Oct) the UniFi 5G Max Outdoor on DNA's network repeatedly fell into a "slow episode":
  downloads from DNA's own test server dropped from 60-200 to **~1.3 Mbit/s** while Cloudflare stayed at 20-60 and the radio looked fine.
- From 20 Oct the episodes came on a strict clock: **one every 6 h 03.8 min**, predicted in advance to the minute (22.10: 4 of 4 within 1 min).
- **Cycling the band profile** (dropping the NR n28 leg for 120 s, profile `0D`, then back to `00`) ended every episode; untreated, one lasted 7.7 h.
- With the automatic watchdog (live from 20 Oct 21:00) episodes lasted ~8 min, at the end ~1 min from onset to cure.
- From 25 Oct the episodes faded (skipped slots, episodes that ended within 3-5 min), the last on the clock was **28 Oct 01:48**, then one weaker,
  off-clock episode on **2 Nov 15:30**, and none since. Nothing was changed on our radio side; an operator-side fix is the likely explanation
  (inference, not confirmed by DNA).

## Timeline
| Date | Event |
|---|---|
| ~20-21 Sep | UniFi speed history starts at ~248 Mbit/s |
| 6 Oct | DNA maintenance; the collapse starts ~7-9 Oct |
| 15 Oct | DNA: nearest sites are south and west of the house |
| 19 Oct | monitoring stack up; episode 1 captured and cured by hand |
| 20 Oct | light probe (1 MB/min) becomes the detector; episode 2 runs 7.7 h untreated; watchdog `live` from 21:00 |
| 21 Oct | first automatic cure; the 6 h 04 min grid found and predicted |
| 22-24 Oct | 12 episodes, all on the grid, all cured automatically |
| 25-27 Oct | the grid holds, but slots are skipped and episodes end by themselves within 3-5 min |
| 28 Oct 01:48 | last episode on the grid; the following slots stay clean |
| 2 Nov 15:30 | one weaker episode off the grid (DNA 4.4 Mbit/s); detected by the fast rule, cured 37 s after its first slow sample |
| 6 Nov ~07:47 | modem firmware 7.5.3 -> 8.0.4 (UniFi), reboot, new management address; the lab's modem-side setup (in RAM) is gone |

## What an episode looked like
- **Destination-dependent:** during an episode DNA's server gave ~1.2-1.6 Mbit/s (a 10 MB download), Cloudflare **12.9-52 times faster**;
  household traffic still reached 40-65 Mbit/s. Upload and ping stayed normal.
- **Reordering:** ~72-78 % of the received TCP segments arrived out of order, exactly 0 after the cure; the 1 MB probe saw 140-330
  out-of-order packets per download (0 in the good state).
- **Not** the radio level (RSRP/SINR, carriers and cells the same in both states), not MTU (a smaller MSS never helped), not household load
  (a 12.6 GB load test did not start one; episodes began at 0 Mbit/s of load), not the UniFi speed test, not a re-attach (IP and session unchanged).
- **Periodic:** onsets on a 6 h 03.8 min grid that cures did not shift - a clock outside our control.

## What cured it, and how fast
The cure removes only NR n28 from the allowed bands for 120 s (custom profile `0D`) and restores profile `00`; the modem drops and re-adds its
NR leg without re-registering. 29 automatic cures in real episodes, every one followed by a fast probe.

| Stage | Detection | Onset -> cure | Onset -> fast again |
|---|---|---|---|
| untreated (episode 2) | - | - | 7.7 h |
| watchdog live, 20-28 Oct | 3 slow samples in a row (2 min) + diag + episode tests | ~6 min | ~8 min |
| final pipeline (from 28 Oct) | one sample >= 3 s with >= 100 out-of-order packets, cure only if the diag confirms | **37 s** (2 Nov) | <= 3.5 min (first sample after the cure) |

False cures: two, both on 29 Oct during heavy household downloads, before the diag check required "Cloudflare >= 5x faster or >= 20 %
reordering". Replayed on the 36 trigger diags of 19-29 Oct, the final check confirms the 31 real episodes and refuses the 5 others; since then it
confirmed the 2 Nov episode and refused 4 load triggers (29 Oct, 3 Nov).

## Where the fault probably was (inference)
The working hypothesis (M1/M1-XS in [FINDINGS.md](FINDINGS.md)): a fault in the **downlink user plane of the NR leg** of this modem's EN-DC
bearer, probably on the transport between the LTE anchor site (SSE) and a different site serving n28 (west). It explains the destination
dependence (loss/reordering-tolerant senders such as Cloudflare suffer less), the heavy reordering (split PDCP), the instant cure by dropping n28,
the unchanged IP/session and the periodic onset (a network-side job). **Not proven:** the NR cell is not reported by the modem, and DNA never
confirmed anything. The planned experiments (antenna turn, second SIM, LTE-only for a day, shorter hold) were not carried out before the
episodes stopped.

## What the lab left behind
- **This repository** (public): code, dashboards, alerts, all day reports. The agent is a container image (`ghcr.io/mvcaaa/u5g-agent`,
  built by `.github/workflows/agent-image.yml`), scheduled by supercronic (`agent/crontab`); nothing runs on the TrueNAS OS.
- **Raw data** (private, not in git, owner's Mac): all metrics since 19 Oct at 60 s (135 metrics, ~7 M rows), 181 Grafana annotations,
  197 diag/test/reference files with pcaps, radio snapshots, the watchdog and probe logs - exported 2026-11-06 with `scripts/export-analysis.py`.
- **For the operator** (if the problem returns): the destination dependence, the reordering numbers and the 6 h 04 min grid with predictions
  made before the fact are the strongest evidence; the question to ask is in FINDINGS.md (n28 from the western site, X2/transport changes on 6 Oct).

## Wind-down
1. Data export and this report (done, 2026-11-06).
2. Watch only: the agent keeps the 1 MB light probe and its alert, no cure and no diagnostics (~1.4 GB/day instead of ~4.3).
3. After 2-3 quiet weeks: stop the TrueNAS apps of the lab. The modem-side files in `/etc/persistent` (dispatcher, band-cycle, the watchdog
   key) and the custom band profile `0D` are the owner's to remove or keep.

## Bringing it back
If the slow episodes return: start the stopped apps (or deploy the compose stack, [DEPLOY.md](DEPLOY.md)); after the 8.0.4 firmware the
modem has a new management address and no SSH on :2222, so re-run `modem/install-modem.sh` (admin password on :22), check that profile `0D`
still exists (`AT!BAND?`), update the modem address of the agent (`deploy/truenas-app-update.sh`) and of the blackbox target, verify
`ping` -> `pong` and a `diag`, and only then set `mode` back to `live` ([OPERATIONS.md](OPERATIONS.md) "After a modem restart").
Known limitation of the final setup: while the watchdog runs a diag and a cure (~3.5 min), supercronic skips the minute light probe, so the
exact recovery time after a cure is not measured.
