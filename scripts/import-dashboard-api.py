#!/usr/bin/env python3
"""Import/overwrite a dashboard JSON in an EXISTING Grafana via the API (the stack's own Grafana provisions dashboards from config/grafana/dashboards/ by itself).
Usage: python3 scripts/import-dashboard-api.py config/grafana/dashboards/u5g-radio-monitor-en.json    env: GRAFANA=http://localhost:30037  GRAFANA_USER=admin  GRAFANA_PASS=...
Overwrites the dashboard with the same uid (the version history in Grafana keeps the old one)."""
import base64, getpass, json, os, sys, urllib.request, urllib.error
if len(sys.argv) != 2: sys.exit(__doc__)
base = os.environ.get("GRAFANA", "http://localhost:30037").rstrip("/")
user = os.environ.get("GRAFANA_USER") or input("Grafana user [admin]: ") or "admin"
pw = os.environ.get("GRAFANA_PASS") or getpass.getpass("Grafana password: ")
dash = json.load(open(sys.argv[1])); dash["id"] = None
req = urllib.request.Request(base + "/api/dashboards/db", method="POST",
    data=json.dumps({"dashboard": dash, "overwrite": True, "message": "import-dashboard-api.py"}).encode())
req.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode())
req.add_header("Content-Type", "application/json")
try:
    print(json.loads(urllib.request.urlopen(req, timeout=30).read()))
except urllib.error.HTTPError as e:
    sys.exit(f"HTTP {e.code}: {e.read().decode()[:400]}")
