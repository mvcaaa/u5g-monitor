#!/usr/bin/env python3
"""Bundle everything needed for an offline analysis of the slow episodes into one directory (read-only towards the live system).
Usage: python3 scripts/export-analysis.py --from 2026-10-18 --to 2026-10-21 --out ~/u5g-analysis [--files <ssh-host>:<watchdog dir>] [--step 60]
env: PROM (Prometheus base URL, default http://localhost:9090); optional GRAFANA, GRAFANA_USER, GRAFANA_PASS for the manual dashboard notes.
Output: metrics/<name>.csv.gz (time, iso, labels, value), annotations.json, files/ (watchdog.log, light probe logs, diag/ incl. pcaps, copied
with rsync over ssh), docs/ (repo docs), README.md. The bundle contains private data (addresses, client names): keep it local, never commit it."""
import argparse, base64, csv, datetime as dt, gzip, json, os, re, shutil, subprocess, sys, time, urllib.parse, urllib.request

METRICS = [r'u5g_.*', r'unpoller_device_(mbb|wan)_.*', r'unpoller_client_(receive|transmit)_rate_bytes', r'probe_success', r'probe_icmp_duration_seconds',
           r'node_textfile_mtime_seconds']
FILES = ['watchdog.log', 'state/light.log', 'state/light-base.log', 'diag/']


def get(url, auth=None):
    req = urllib.request.Request(url, headers={'Authorization': auth} if auth else {})
    return json.loads(urllib.request.urlopen(req, timeout=120).read())


def ts(s):
    d = dt.datetime.fromisoformat(s)
    return (d if d.tzinfo else d.astimezone()).timestamp()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--from', dest='start', required=True, help='local time, ISO (2026-10-20 or 2026-10-20T18:00)')
    ap.add_argument('--to', dest='end', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--step', type=int, default=60, help='seconds between points (default 60)')
    ap.add_argument('--files', help='rsync source of the watchdog dir, e.g. truenas:/mnt/Main/u5g-watchdog')
    a = ap.parse_args()
    prom = os.environ.get('PROM', 'http://localhost:9090').rstrip('/')
    start, end = ts(a.start), ts(a.end)
    out = os.path.expanduser(a.out)
    os.makedirs(os.path.join(out, 'metrics'), exist_ok=True)

    names = [n for n in get(prom + '/api/v1/label/__name__/values')['data']
             if any(re.fullmatch(p, n) for p in METRICS)]
    chunk = a.step * 10000  # Prometheus returns at most 11000 points per series and query
    rows_total = 0
    for name in sorted(names):
        with gzip.open(os.path.join(out, 'metrics', name + '.csv.gz'), 'wt', newline='') as f:
            w = csv.writer(f); w.writerow(['time', 'iso', 'labels', 'value'])
            t = start
            while t < end:
                q = urllib.parse.urlencode({'query': name, 'start': t, 'end': min(t + chunk, end), 'step': a.step})
                for r in get(f'{prom}/api/v1/query_range?{q}')['data']['result']:
                    lab = json.dumps({k: v for k, v in r['metric'].items() if k != '__name__'}, sort_keys=True)
                    for tt, v in r['values']:
                        w.writerow([int(tt), dt.datetime.fromtimestamp(tt).isoformat(), lab, v]); rows_total += 1
                t += chunk + a.step
    print(f'metrics: {len(names)} names, {rows_total} rows')

    ann = []
    if os.environ.get('GRAFANA') and os.environ.get('GRAFANA_PASS'):
        auth = 'Basic ' + base64.b64encode(f"{os.environ.get('GRAFANA_USER', 'admin')}:{os.environ['GRAFANA_PASS']}".encode()).decode()
        q = urllib.parse.urlencode({'from': int(start * 1000), 'to': int(end * 1000), 'limit': 5000})
        ann = get(os.environ['GRAFANA'].rstrip('/') + '/api/annotations?' + q, auth)
        print(f'annotations: {len(ann)}')
    json.dump(ann, open(os.path.join(out, 'annotations.json'), 'w'), indent=1)

    if a.files:
        os.makedirs(os.path.join(out, 'files'), exist_ok=True)
        src = a.files.rstrip('/')
        host, _, path = src.partition(':')
        r = subprocess.run(['rsync', '-a', '--relative', '--chmod=u+rw'] + [f'{host}:{path}/./{f}' for f in FILES] + [os.path.join(out, 'files')])
        print('files: copied from', src, '' if r.returncode == 0 else f'(rsync exit {r.returncode}: some files missing)')

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shutil.copytree(os.path.join(here, 'docs'), os.path.join(out, 'docs'), dirs_exist_ok=True)
    with open(os.path.join(out, 'README.md'), 'w') as f:
        f.write(f"""# u5g-monitor analysis bundle
Exported {time.strftime('%F %T %Z')} for {a.start} .. {a.end} (local time), step {a.step} s.
- `metrics/<name>.csv.gz`: one row per point: unix time, local ISO time, labels (JSON), value. Light probe = `u5g_probe_light_time_seconds`
  (detector input), watchdog state = `u5g_watchdog_*`, episode/reference tests = `u5g_eptest_*{{kind}}`, radio = `unpoller_device_mbb_*`
  (cell/band in `unpoller_device_mbb_info` labels), carriers = `u5g_ca_*`, household traffic = `unpoller_device_wan_*` and per client `unpoller_client_*`.
- `annotations.json`: Grafana annotations incl. manual notes (empty if no Grafana credentials were given).
- `files/`: watchdog.log, light probe logs, diag/episode-*.txt (before cure), *-after.txt (after cure), *-tests.txt/.pcap, reference-*.
- `docs/`: FINDINGS.md (hypotheses), episodes/, baselines/, METRICS.md (metric meanings), OPERATIONS.md.
Private data (addresses, client names): keep local.
""")
    print('bundle:', out)


if __name__ == '__main__':
    sys.exit(main())
