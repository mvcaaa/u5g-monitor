# Metrics

## Written by `agent/probe.sh` (`data/textfile/u5g_probe.prom`, every 5 min, diagnostics only - not used for detection)
| Metric | Labels | Meaning |
|---|---|---|
| `u5g_probe_http_code` / `_bytes` / `_duration_seconds` | `target=dna\|cloudflare` | result of the 5 MB download |
| `u5g_probe_download_bits_per_second` | `target` | single-stream speed. Good state ≈ 60-100 Mbit/s on 5 MB; episode: DNA ≈ 1-5 |
| `u5g_probe_tcp_in_segments` / `_ofo_queued` / `_dsack_sent` | | receiver-side TCP counters during the DNA download (loss/reordering evidence; retransmits are counted at the sender, so for downloads use these) |
| `u5g_probe_loaded_rtt_avg_seconds` / `_max_seconds` / `u5g_probe_loaded_loss_ratio` | | ping to nopeus.dna.fi *during* the download (bufferbloat / queueing) |
| `u5g_probe_ping_rtt_avg_seconds`, `u5g_probe_ping_loss_ratio` | `size=56\|1472` | idle ping, small vs full-MTU packet with DF |
| `u5g_public_ip_info` | `ip` | current public IPv4 (value 1) |
| `u5g_probe_last_run_timestamp_seconds` | | freshness |

## Written by `agent/watchdog.sh` (`data/textfile/u5g_watchdog.prom`)
`u5g_watchdog_episode_active` (0/1), `_detections_total` (episode starts), `_light_baseline_seconds` (median of good-state light times), `_light_threshold_seconds` (current detection threshold), `_light_baseline_samples`, `_live_mode` (0 dry / 1 live), `_modem_reachable` (0/1), `_cures_total`,
`_dryrun_triggers_total`, `_last_cure_result` (-1 none, 0 failed, 1 ok), `_last_cure_timestamp_seconds`,
`_triggers_today`, `_probe_fresh` (light probe sample younger than 10 min), `_last_run_timestamp_seconds`.
Retired on 2026-10-20: `u5g_watchdog_light_fresh`, `_light_episode_active`, `_light_primary`, `_light_detections_total`. Their history stays in Prometheus until retention drops it.

## Written by `agent/episode-tests.sh` (`data/textfile/u5g_eptest.prom`, once per triggered episode, before any cure; also by a manual run)
| Metric | Labels | Meaning |
|---|---|---|
| `u5g_eptest_ping_loss_ratio`, `u5g_eptest_ping_rtt_avg_seconds` | `target=dna\|cloudflare`, `size=56\|1000\|1200\|1400\|1472` | 100 DF pings per size |
| `u5g_eptest_download_bits_per_second` / `_bytes` / `_http_code` / `_rcv_mss_bytes` | `run=1..4`, `mss=default\|1200\|1000` | 5 MB from DNA with the requested MSS (runs 1 and 4 use the default); `rcv_mss` = segment size the receiver saw |
| `u5g_eptest_duration_seconds`, `u5g_eptest_last_run_timestamp_seconds` | | how long the tests took and when they ran |
Values stay until the next run (the file is not removed). The text report of a triggered run is `data/diag/episode-<time>-tests.txt`.

## Other sources
`probe_success`, `probe_icmp_duration_seconds{phase="rtt"}` (blackbox);
`unpoller_*` (UniFi).

## From json_exporter (job `u5g_ca`, every minute, UniFi controller `stat/device`, the U5G entry `model=="UMBBE631"`)
`u5g_ca_lte_present{band,earfcn,primary}`, `u5g_ca_lte_dl_bw_mhz`, `u5g_ca_lte_ul_bw_mhz`; `u5g_ca_nr_present{band,dl_arfcn,primary}`, `u5g_ca_nr_dl_bw_mhz`,
`u5g_ca_nr_ul_bw_mhz` (one series per component carrier currently in aggregation; `primary="false"` = secondary carrier);
`u5g_last_seen_timestamp_seconds` (when the controller last heard from the U5G - data freshness). Config: `config/json_exporter/json_exporter.yml`.

## Written by `agent/probe-light.sh` (`data/textfile/u5g_probe_light.prom`, every minute)
`u5g_probe_light_last_run_timestamp_seconds`, `_http_code`, `_bytes`, `_time_seconds` (total time of the 1 MB download from DNA - the quantity that is judged),
`_download_bits_per_second` (informational only: slow start makes the speed of a 1 MB file unreliable). Raw samples: `data/state/light.log`.
