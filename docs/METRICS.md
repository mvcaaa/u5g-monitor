# Metrics

## Written by `agent/probe.sh` (`data/textfile/u5g_probe.prom`)
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
`u5g_watchdog_episode_active` (0/1), `_live_mode` (0 dry / 1 live), `_modem_reachable` (0/1), `_cures_total`,
`_dryrun_triggers_total`, `_last_cure_result` (-1 none, 0 failed, 1 ok), `_last_cure_timestamp_seconds`,
`_triggers_today`, `_probe_fresh`, `_last_run_timestamp_seconds`.

## Other sources
`speedtest_tracker_download_bits`, `speedtest_tracker_upload_bits`, `speedtest_tracker_*_ms` (labels incl. `scheduled`,
so always aggregate with `max(...)`); `probe_success`, `probe_icmp_duration_seconds{phase="rtt"}` (blackbox);
`unpoller_*` (UniFi). `u5g_ca_*` come from a json_exporter job that is NOT part of this repo (KNOWN_GAPS.md).
