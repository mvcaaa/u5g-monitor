# Light probe calibration, good state, 2026-10-19 19:37

20 sequential downloads of `http://nopeus.dna.fi:8080/download?size=1000000`, 3 s apart (modem in good state, after the first episode's cure):

| metric | value |
|---|---|
| HTTP codes | 20 x 200 |
| time_total | min 0.31 s, typical 0.3-0.6 s, max 0.79 s |
| average speed | 10.1 - 25.6 Mbit/s (the lowest value is close to the 8 Mbit/s threshold of the 5 MB probe, so a 1 MB file must not be judged by speed) |

Raw samples (s / Mbit/s): 0.35/23.0, 0.60/13.4, 0.32/25.2, 0.36/22.1, 0.43/18.4, 0.44/18.3, 0.79/10.1, 0.47/16.9, 0.55/14.5, 0.32/24.9,
0.43/18.5, 0.59/13.5, 0.31/25.6, 0.34/23.7, 0.64/12.5, 0.45/17.8, 0.45/17.6, 0.53/15.1, 0.32/24.8, 0.41/19.6.

Threshold chosen: **>= 2.0 s** (2.5 x the worst good sample; corresponds to an average of about 4 Mbit/s or less). In the slow state DNA gave ~1.2-1.5 Mbit/s (5 MB probe), i.e. ~6 s for 1 MB or a timeout at 5 s.
Mild episodes (5-14 Mbit/s) are not separable at this size.
