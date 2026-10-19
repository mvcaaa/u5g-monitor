# Findings so far (evidence base; dates 2026)

## Symptom
Download speed on the U5G alternates between a **good** state (~180-250 Mbit/s in Speedtest, ~60-100 Mbit/s single-stream 5 MB probe)
and a **bad** state (5-14 Mbit/s). UniFi's own speed history is bimodal: bad plateau 11-14, good 183-248. History starts ~20-21 Sep (≈248 Mbit/s);
the collapse began ~7-9 Oct, after DNA's maintenance on 6 Oct. Episodes do not end by themselves (hours-long: the 19 Oct episode started ~07:00 and was still present ~6 h later, when it was cured manually).
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

## Traceroute (good state) to nopeus.dna.fi
`172.20.47.1` → `172.20.47.2/.0/.3` → `62.197.175.66` → `62.197.175.67` (destination), ~35 ms; hops 1-2 are CGNAT-internal. Compare with an episode's `diag`.

## Calibration (U5G local, Cloudflare `__down?bytes=`; bytes ≤ ~50 MB, larger returns 1 byte)
Good: single 10 MB ≈ 70 Mbit/s, single 50 MB ≈ 106, 4×10 MB parallel ≈ 182. Bad: single 10 MB ≈ 46-50 to Cloudflare while DNA ≈1-5.
Host probe, good state (5 MB): DNA ≈ 66 Mbit/s, loaded RTT ≈ 47 ms avg / 95 max, 0 loss; idle ping 56 B ≈ 37 ms, 1472 B ≈ 47 ms.

## Open questions (what the next episode should answer)
1. ~~Does `diag` during an episode show anything different?~~ Answered by the first episode, see [episodes/2026-10-19-episode-1.md](episodes/2026-10-19-episode-1.md): heavy TCP reordering (OFO) in the bad state for all destinations, no LTE secondary carrier in GSTATUS, clean ICMP/traceroute, stable radio; none of it shown to be the cause.
2. Does a lighter action (`AT+CGATT=0/1`) cure it? Does staying in profile `0D` for an hour behave differently?
3. Is the degradation specific to DNA's own servers/paths (nopeus) or to a set of destinations? Add a third probe target (Google/OVH) if needed.
4. Evidence package for DNA: UniFi multi-day graph, Grafana panel of an episode with annotations, `diag` files, before/after table.
