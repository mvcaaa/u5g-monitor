# Findings so far (evidence base; dates 2026)

## Symptom
Download speed on the U5G alternates between a **good** state (~180-250 Mbit/s in Speedtest, ~60-100 Mbit/s single-stream 5 MB probe)
and a **bad** state (5-14 Mbit/s). UniFi's own speed history is bimodal: bad plateau 11-14, good 183-248. History starts ~20-21 Sep (≈248 Mbit/s);
the collapse began ~7-9 Oct, after DNA's maintenance on 6 Oct. Episodes last hours (the 19 Oct episode started ~07:00 and was still present ~6 h later, when it was cured manually) and can end by themselves
(episode 2 on 20 Oct: ~7.7 h, no cure, see [episodes/2026-10-20-episodes-2-3.md](episodes/2026-10-20-episodes-2-3.md)). They happen at night and at midday, so evening peak load is not the cause.
An indoor 5G router (Xiaomi-type, likely on the same SIM) at the south window never showed this; a phone with a DNA SIM at the same spot always outperforms the U5G
during an episode (92/13 Mbit/s). n78 (3.5 GHz) is unavailable in the area; the unlimited plan is capped at 300 Mbit/s.

## What the bad state is NOT
- **Not a radio-capacity collapse and not caused by radio configuration.** Radio KPIs (RSRP, SINR ≈ 20 dB, NR n28) look good in both states.
  The same config (cells A/B, B3/B1, n28 ARFCN 152600/156600) delivered fast and slow at different times, in both directions
  (e.g. cell A gave 189/213 Mbit/s at 23:59-00:07 and 5 Mbit/s at 01:07). On 19 Oct 14:10 the modem sat on cell A / 152600 in the *good* state.
- Not a shaper with a burst allowance (a sustained 4×50 MB test ran at 151 Mbit/s over 37 s).
- Not port, plain-HTTP-vs-TLS, or IPv4-vs-IPv6 (all ruled out); not UXG/TrueNAS (not the bottleneck); public IPv4 unchanged by the cure.

## What the bad state IS (destination-dependent)
During an episode (19 Oct, same minutes): Cloudflare ≈130-150 Mbit/s; **`nopeus.dna.fi` ≈1-1.6 Mbit/s single stream, ≈4.3 aggregate**;
Google 5-12; OVH ≈65. After the cure **every** destination ≈97-109 Mbit/s. Ping stays normal (29-38 ms, no loss), upload stays ~116 Mbit/s.
Hypothesis: path/destination-dependent degradation tied to the session/bearer/core state, reset by re-registration (the band cycle is a lighter reset
than a detach; modem uptime was 5.6 days, reset counter 1 - there was no real outage). Root cause on DNA's side is **unknown**.
Recovery does not always hold: the multi-day UniFi speed graphs show relapses after manual cures.

## What the cure actually changes (2026-10-20, from Prometheus/UniFi data around 3 episodes and 2 cures)
The modem runs **EN-DC (5G NSA)**: LTE anchor (B3, with B1 as a flapping LTE secondary) plus NR n28 (10 MHz) as the secondary cell group (SCG).
Profile `0D` differs from `00` **only** in the NR-NSA mask (n28 removed), so the cure is "drop the NR leg for 120 s, then allow it again".

| | at each cure | at episode onset/offset (00:45, 08:30, 12:55) |
|---|---|---|
| NR n28 leg | gone ~2 min, then back | present throughout, no gap at 1-minute resolution |
| LTE primary carrier | episode 1: B3 unchanged; episode 3: B3 -> B1 -> B3 | unchanged (B3) |
| registration / SIM session (`sim_state_seconds`), public IP | no reset | no reset |
| NR SNR | ~20 dB | ~20 dB |

- The only change common to both cures is the **release and re-addition of the NR leg**. Recovery happened **while NR was off** (episode 3, confirmed
  by the light probe and by the owner), with the LTE primary unchanged in episode 1.
- The PDN session in the core (and with it the IP and any per-session policy/PCC rules at the PGW) was apparently not re-created. This **weakens the
  "per-session operator policy" hypothesis**, unless that policy depends on the radio access in use.
- Upload stays normal (~116 Mbit/s) during episodes; the NR transmitter is barely used (NR Tx power -30 dBm in some diags), i.e. uplink rides on LTE.

**Working hypothesis (M1, inference, not proven):** the fault sits in the **downlink user plane of the NR leg** of this UE's bearer: the gNB-side
bearer context, its GTP-U tunnel (in EN-DC option 3x the S1-U tunnel ends at the gNB, which splits PDCP between NR and LTE over X2-U), or the
transport path chosen for that tunnel (e.g. one bad ECMP member, or an MTU problem with GTP overhead). Releasing the SCG removes all of that and sends
traffic straight to the LTE eNB; re-adding NR builds a fresh context. It fits: same IP, no re-attach, recovery on LTE only, downlink-only impact, heavy
reordering (PDCP split), destination dependence via the senders' congestion control (loss/reordering-tolerant BBR at Cloudflare vs others), and
spontaneous start/end (the network can rebuild the SCG context in seconds, below our 1-minute sampling). Other UEs (indoor router, phone) being
unaffected does not contradict it: the context is per UE. Whether those devices used n28 NSA is not known.

Tests that would confirm or refute M1 (only during an episode, with the owner's go-ahead): a short hold (`band-cycle.sh 20`); packet-size ping and
reduced-MSS downloads (size-dependent loss on the NR leg); staying LTE-only (`0D`) for a longer period and checking that no episode occurs.

## Load as a trigger? (2026-10-20)
Episode onsets 1 and 2 fell inside long, heavy household downloads (45-92 Mbit/s for 10-40 min), onset 3 came 8 min after a 39 Mbit/s burst;
but bursts >= 30 Mbit/s happened 51 times in ~26 h. A deliberate test did **not** start an episode: 10 rounds of 60 s x 8 parallel downloads from
`nopeus.dna.fi` (139-184 Mbit/s, ~12.6 GB, 16:20-17:10) with the light probe normal in every pause (an earlier Cloudflare run was cut short by
Cloudflare's 429 rate limit after ~1.7 GB). Short bursts are therefore not a reliable trigger; long mixed-destination load is still open.
During episodes the household WAN traffic still reached 40-65 Mbit/s aggregate while DNA's light probe stayed at ~1.5 Mbit/s: capacity is there,
only some flows suffer.
Episode 4 (18:57) started with **no** load at all (household download 1-4 Mbit/s for the 15 minutes before), so load is at most one of several
triggers ([episodes/2026-10-20-episode-4.md](episodes/2026-10-20-episode-4.md)).

## Traceroute (good state) to nopeus.dna.fi
`172.20.47.1` → `172.20.47.2/.0/.3` → `62.197.175.66` → `62.197.175.67` (destination), ~35 ms; hops 1-2 are CGNAT-internal. Compare with an episode's `diag`.

## Calibration (U5G local, Cloudflare `__down?bytes=`; bytes ≤ ~50 MB, larger returns 1 byte)
Good: single 10 MB ≈ 70 Mbit/s, single 50 MB ≈ 106, 4×10 MB parallel ≈ 182. Bad: single 10 MB ≈ 46-50 to Cloudflare while DNA ≈1-5.
Host probe, good state (5 MB): DNA ≈ 66 Mbit/s, loaded RTT ≈ 47 ms avg / 95 max, 0 loss; idle ping 56 B ≈ 37 ms, 1472 B ≈ 47 ms.

## Open questions (what the next episode should answer)
1. ~~Does `diag` during an episode show anything different?~~ Answered by the first episode, see [episodes/2026-10-19-episode-1.md](episodes/2026-10-19-episode-1.md): clean ICMP/traceroute, stable radio, heavy TCP reordering (but it also returns after the cure and tracks carrier aggregation), LTE B1 flapping in both states; nothing on the modem side separates good from bad. DNA ~1 Mbit/s vs Cloudflare uneven.
2. Does a shorter hold (20 s) or a lighter action (`AT+CGATT=0/1`) cure it? Do episodes occur at all in LTE-only (`0D`), and what capacity does LTE alone give?
3. Is the degradation specific to DNA's own servers/paths (nopeus) or to a set of destinations? Add a third probe target (Google/OVH) if needed.
4. Evidence package for DNA: UniFi multi-day graph, Grafana panel of an episode with annotations, `diag` files, before/after table.
