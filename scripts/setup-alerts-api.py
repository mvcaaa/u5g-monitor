#!/usr/bin/env python3
"""Create the U5G alert rules in an EXISTING Grafana (not the one provisioned by this stack) via the provisioning API. Idempotent (skips existing titles).
Keep in sync with config/grafana/provisioning/alerting/rules.yml.
Usage: python3 scripts/setup-alerts-api.py [--dry]    env: GRAFANA=http://localhost:30037  GRAFANA_USER=admin  GRAFANA_PASS=...  CONTACT=telegram
"""
import base64, getpass, json, os, sys, urllib.request, urllib.error

DRY = "--dry" in sys.argv
BASE = os.environ.get("GRAFANA", "http://localhost:30037").rstrip("/")
CONTACT = os.environ.get("CONTACT", "telegram")
FOLDER = "U5G"
GROUP = "u5g-watchdog"

RULES = [
  # title, promql (value > 0 fires), for, noData, summary, window seconds
  ("U5G: cure executed", "increase(u5g_watchdog_cures_total[10m])", "0s", "OK",
   "Watchdog sent a cure (band cycle) to the modem. Check watchdog.log and diag/episode-*.txt on TrueNAS.", 700),
  ("U5G: cure did not help", "u5g_watchdog_last_cure_result == bool 0", "0s", "OK",
   "The last cure did not restore DNA speed above the threshold. Manual attention needed.", 600),
  ("U5G: episode detected (dry-run)", "increase(u5g_watchdog_dryrun_triggers_total[10m])", "0s", "OK",
   "Watchdog detected a slow-DNA episode in dry-run mode (no cure sent). diag saved on TrueNAS.", 700),
  ("U5G: episode started", "increase(u5g_watchdog_confirmed_total[10m])", "0s", "OK",
   "An episode was detected by the light probe and confirmed by the diag (DNA download below the confirmation threshold); the cure follows in live mode.", 700),
  ("U5G: modem unreachable by watchdog", "1 - u5g_watchdog_modem_reachable", "10m", "Alerting",
   "TrueNAS cannot reach the modem on ssh port 2222 (modem rebooted? dropbear on 2222 not running?). Auto-cure is blocked.", 900),
  ("U5G: probe is stale", "time() - u5g_probe_light_last_run_timestamp_seconds - 300", "5m", "Alerting",
   "probe-light.sh has not updated metrics for over 5 minutes (cron or node-exporter problem); episodes cannot be detected.", 1200),
  ("U5G: watchdog is stale", "time() - u5g_watchdog_last_run_timestamp_seconds - 900", "5m", "Alerting",
   "watchdog.sh has not run for over 15 minutes.", 1200),
]

if DRY:
    user = pw = ""
else:
    user = os.environ.get("GRAFANA_USER") or input("Grafana user [admin]: ") or "admin"
    pw = os.environ.get("GRAFANA_PASS") or getpass.getpass("Grafana password: ")
AUTH = "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()


def api(method, path, body=None, extra=None):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", AUTH)
    req.add_header("Content-Type", "application/json")
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} on {method} {path}: {e.read().decode()[:500]}")


def rule(title, expr, for_, nodata, summary, window, ds_uid, folder_uid):
    return {
        "title": title, "ruleGroup": GROUP, "folderUID": folder_uid, "orgID": 1,
        "condition": "C", "for": for_, "noDataState": nodata, "execErrState": "Error",
        "annotations": {"summary": summary},
        "labels": {"project": "u5g"},
        "notification_settings": {"receiver": CONTACT},
        "data": [
            {"refId": "A", "relativeTimeRange": {"from": window, "to": 0}, "datasourceUid": ds_uid,
             "model": {"refId": "A", "expr": expr, "instant": True, "intervalMs": 1000, "maxDataPoints": 43200}},
            {"refId": "B", "datasourceUid": "__expr__", "relativeTimeRange": {"from": window, "to": 0},
             "model": {"refId": "B", "type": "reduce", "expression": "A", "reducer": "last",
                       "settings": {"mode": "dropNN"}}},
            {"refId": "C", "datasourceUid": "__expr__", "relativeTimeRange": {"from": window, "to": 0},
             "model": {"refId": "C", "type": "threshold", "expression": "B",
                       "conditions": [{"evaluator": {"type": "gt", "params": [0]}}]}},
        ],
    }


if DRY:
    ds_uid, folder_uid, existing = "DS_UID", "FOLDER_UID", set()
else:
    dss = [d for d in api("GET", "/api/datasources") if d["type"] == "prometheus"]
    if not dss:
        sys.exit("No Prometheus datasource found")
    ds_uid = dss[0]["uid"]
    print("datasource:", dss[0]["name"], ds_uid)
    folders = [f for f in api("GET", "/api/folders") if f["title"] == FOLDER]
    folder_uid = folders[0]["uid"] if folders else api("POST", "/api/folders", {"title": FOLDER})["uid"]
    existing = {r["title"] for r in api("GET", "/api/v1/provisioning/alert-rules")}

for r in RULES:
    payload = rule(*r, ds_uid, folder_uid)
    if DRY:
        print(json.dumps(payload)[:300]); continue
    if r[0] in existing:
        print("exists, skipped:", r[0]); continue
    api("POST", "/api/v1/provisioning/alert-rules", payload, {"X-Disable-Provenance": "true"})
    print("created:", r[0])
