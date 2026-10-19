# Good-state reference measurements (19 Oct 2026, ~14:10 local; no episode active)

Serving cell A (PCI 23), n28 Rx chan 152600 (10 MHz), LTE SINR 18.6 dB, RSRQ -10.2, NR5G RSRP -68 dBm, SINR 22.7 dB, RRC connected,
IMS not registered (irrelevant). This is the *same cell/ARFCN* that was present in bad episodes → radio state does not discriminate.

| Test (from modem `diag`) | Run 1 | Run 2 |
|---|---|---|
| ping nopeus.dna.fi 56 B (min/avg/max ms) | 31.5 / 37.2 / 42.4 | 26.7 / 71.4 / 227 (one outlier) |
| ping nopeus.dna.fi 1400 B | 31.8 / 40.5 / 48.2 | 28.8 / 34.8 / 37.1 |
| ping 1.1.1.1 56 B | 35.4 / 52.8 / 117 | 29.2 / 38.2 / 44.5 |
| 10 MB download nopeus.dna.fi:8080 | 7.40 MB/s (≈59 Mbit/s) | 3.77 MB/s (≈30 Mbit/s) |
| 10 MB download Cloudflare | 7.59 MB/s (≈61 Mbit/s) | 9.02 MB/s (≈72 Mbit/s) |
| TCP receiver delta (retrans / OFO / DSACK) | n/a (full counters) | 0 / 0 / 0 over 14 680 segments |
Traceroute to nopeus.dna.fi (62.197.175.67): 172.20.47.1 → 172.20.47.2/.0 → 62.197.175.66 → 62.197.175.67, ≈30-45 ms per hop (hop 3 once 92 ms).
Host probe (5 MB, via TrueNAS): DNA 66 Mbit/s (0.6 s), Cloudflare 64.6, loaded RTT 46.8 ms avg / 94.6 max, loss 0; later DNA samples 28 Mbit/s - single-stream
5-10 MB tests vary 2× inside the good state. An episode looks like DNA ≈ 1-5 Mbit/s with Cloudflare still ≥ 60.
