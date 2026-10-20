#!/usr/bin/env python3
"""Compare radio and speed metrics between time windows (e.g. antenna positions). Read-only.
Usage: PROM=http://<prometheus> python3 scripts/compare-windows.py "before=2026-10-21T10:00/2026-10-21T11:00" "205=2026-10-21T11:10/2026-10-21T11:45" ...
Times are local unless they carry an offset. Prints the mean (and sample count) of each metric per window, plus the carriers seen."""
import datetime as dt, json, os, sys, urllib.parse, urllib.request

PROM = os.environ.get('PROM', 'http://localhost:9090').rstrip('/')
ROWS = [  # label, PromQL (one series), source cadence
    ('LTE RSRP rx0..3 avg, dBm', 'avg(u5g_radio_lte_rsrp_dbm)', '5 min'),
    ('LTE SINR, dB', 'u5g_radio_lte_sinr_db', '5 min'),
    ('LTE RSRQ, dB', 'u5g_radio_lte_rsrq_db', '5 min'),
    ('LTE Tx power, dBm', 'u5g_radio_lte_tx_power_dbm', '5 min'),
    ('NR RSRP, dBm', 'u5g_radio_nr_rsrp_dbm', '5 min'),
    ('NR SINR, dB', 'u5g_radio_nr_sinr_db', '5 min'),
    ('NR Tx power, dBm', 'u5g_radio_nr_tx_power_dbm', '5 min'),
    ('LTE RSRP (UniFi), dBm', 'max(unpoller_device_mbb_rsrp_dbm)', '1 min'),
    ('LTE SNR (UniFi), dB', 'max(unpoller_device_mbb_snr_db)', '1 min'),
    ('NR RSRP (UniFi), dBm', 'max(unpoller_device_mbb_nr_rsrp_dbm)', '1 min'),
    ('NR SNR (UniFi), dB', 'max(unpoller_device_mbb_nr_snr_db)', '1 min'),
    ('light probe 1 MB, s', 'u5g_probe_light_time_seconds', '1 min'),
    ('DNA 5 MB, Mbit/s', 'u5g_probe_download_bits_per_second{target="dna"} / 1e6', '5 min'),
    ('Cloudflare 5 MB, Mbit/s', 'u5g_probe_download_bits_per_second{target="cloudflare"} / 1e6', '5 min'),
]


def ts(s):
    d = dt.datetime.fromisoformat(s)
    return (d if d.tzinfo else d.astimezone()).timestamp()


def series(q, a, b):
    u = f'{PROM}/api/v1/query_range?' + urllib.parse.urlencode({'query': q, 'start': a, 'end': b, 'step': 60})
    return json.loads(urllib.request.urlopen(u, timeout=60).read())['data']['result']


def main():
    wins = []
    for arg in sys.argv[1:]:
        name, _, span = arg.partition('=')
        a, _, b = span.partition('/')
        if not (name and a and b):
            sys.exit(__doc__)
        wins.append((name, ts(a), ts(b)))
    if not wins:
        sys.exit(__doc__)
    w = 30
    print(f"{'metric':{w}}" + ''.join(f'{n:>16}' for n, _, _ in wins))
    for label, q, cad in ROWS:
        cells = []
        for _, a, b in wins:
            vals, seen = [], set()
            for r in series(q, a, b):
                for t, v in r['values']:
                    if t not in seen:
                        seen.add(t); vals.append(float(v))
            # a 5-min source repeats its value on every 1-min step: count value changes as the approximate number of real samples
            real = [v for i, v in enumerate(vals) if i == 0 or v != vals[i - 1]]
            cells.append(f'{sum(vals) / len(vals):8.1f} (n{len(real):>3})' if vals else f"{'-':>16}")
        print(f'{label:{w}}' + ''.join(f'{c:>16}' for c in cells))
    print('\ncarriers (lte_rx_chan / nr_rx_chan / cell_id) seen per window:')
    for n, a, b in wins:
        combos = sorted({f"{r['metric'].get('lte_rx_chan')}/{r['metric'].get('nr_rx_chan')}/{r['metric'].get('cell_id')}" for r in series('u5g_radio_info', a, b)})
        print(f'  {n}: ' + (', '.join(combos) or '-'))
    print('\nn = distinct values seen (approximate number of real samples for 5-min sources). Compare only windows with the same carriers.')


if __name__ == '__main__':
    main()
