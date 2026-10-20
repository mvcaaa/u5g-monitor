# Metrics

## Written by `agent/watchdog.sh` (`data/textfile/u5g_watchdog.prom`)
`u5g_watchdog_episode_active` (0/1), `_detections_total` (episode starts), `_light_baseline_seconds` (median of good-state light times), `_light_threshold_seconds` (current detection threshold), `_light_baseline_samples`, `_live_mode` (0 dry / 1 live), `_modem_reachable` (0/1), `_cures_total`,
`_dryrun_triggers_total`, `_last_cure_result` (-1 none, 0 failed, 1 ok), `_last_cure_timestamp_seconds`,
`_triggers_today`, `_probe_fresh` (light probe sample younger than 10 min), `_last_run_timestamp_seconds`.
Retired on 2026-10-20 with `agent/probe.sh` (5 MB DNA/Cloudflare probe): `u5g_probe_download_bits_per_second`, `u5g_probe_tcp_*`, `u5g_probe_loaded_*`, `u5g_probe_ping_*`,
`u5g_public_ip_info`, `u5g_probe_last_run_timestamp_seconds`; also `u5g_watchdog_light_fresh`, `_light_episode_active`, `_light_primary`, `_light_detections_total`. Their history stays in Prometheus until retention drops it.

## Other sources
`speedtest_tracker_download_bits`, `speedtest_tracker_upload_bits`, `speedtest_tracker_*_ms` (labels incl. `scheduled`,
so always aggregate with `max(...)`); `probe_success`, `probe_icmp_duration_seconds{phase="rtt"}` (blackbox);
`unpoller_*` (UniFi).

## From json_exporter (job `u5g_ca`, every minute, UniFi controller `stat/device`, the U5G entry `model=="UMBBE631"`)
`u5g_ca_lte_present{band,earfcn,primary}`, `u5g_ca_lte_dl_bw_mhz`, `u5g_ca_lte_ul_bw_mhz`; `u5g_ca_nr_present{band,dl_arfcn,primary}`, `u5g_ca_nr_dl_bw_mhz`,
`u5g_ca_nr_ul_bw_mhz` (one series per component carrier currently in aggregation; `primary="false"` = secondary carrier);
`u5g_last_seen_timestamp_seconds` (when the controller last heard from the U5G - data freshness). Config: `config/json_exporter/json_exporter.yml`.

## Written by `agent/probe-light.sh` (`data/textfile/u5g_probe_light.prom`, every minute)
`u5g_probe_light_last_run_timestamp_seconds`, `_http_code`, `_bytes`, `_time_seconds` (total time of the 1 MB download from DNA - the quantity that is judged),
`_download_bits_per_second` (informational only: slow start makes the speed of a 1 MB file unreliable). Raw samples: `data/state/light.log`.
