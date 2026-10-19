# Grafana MCP (read-only access for an AI assistant)

An MCP server lets an assistant such as Claude Code query the live stack itself: PromQL against the Prometheus datasource, dashboards and their
panel queries, alert rules and their state, annotations. It uses the official [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana)
through `scripts/mcp-grafana.sh`. Nothing here is needed for monitoring to work.

## Safety model
- Grafana service account with role **Viewer**: the token cannot change dashboards, rules, contact points or users.
- `--disable-write` removes the write tools; `--enabled-tools` keeps only search, datasource, prometheus, alerting, dashboard, folder,
  annotations (no raw API proxy, no provisioning/config/admin tools). `alerting_manage_routing` is still listed; the Viewer role is what stops it.
- The token is never stored in a config file: `scripts/mcp-grafana.sh` reads it at start (`op read`, 1Password CLI) or from the environment.
- Prometheus itself has no auth in this stack; anyone on the LAN can already query it at `:9090` (TrueNAS: the Prometheus app port).

## Setup
1. **Service account** (Grafana admin, once): Administration -> Users and access -> Service accounts -> Add, name `claude-mcp`, role `Viewer`
   -> Add service account token. Or with the API:
   `POST /api/serviceaccounts {"name":"claude-mcp","role":"Viewer"}`, then `POST /api/serviceaccounts/<id>/tokens {"name":"<machine>"}`.
   Store the token (`glsa_...`) in the password manager right away; it is shown only once.
2. **Requirements on the workstation:** `uv` (provides `uvx`), and `op` if the token comes from 1Password.
3. **Register** (Claude Code, only for this project on this machine; the values are a URL and a secret *reference*, not the secret):
   ```bash
   claude mcp add --scope local grafana-u5g -e GRAFANA_URL=http://<grafana_host>:<port> -e GRAFANA_TOKEN_OP_REF=op://<vault>/<item>/credential -- bash "$PWD/scripts/mcp-grafana.sh"
   ```
   The name must come before `-e` (it takes several values and would swallow the name).
   Restart Claude Code; the tools appear as `mcp__grafana-u5g__*`.
4. **Check:** `claude mcp get grafana-u5g` shows `Connected`; in the assistant run `check_datasources_health` and an instant
   `query_prometheus` such as `u5g_ca_lte_present`, and compare with Prometheus directly (`/api/v1/query?query=u5g_ca_lte_present`).

## Notes
- `query_prometheus` needs the datasource uid. In the provisioned stack it is `prometheus`; a hand-built Grafana has a generated uid
  (`list_datasources` shows it).
- `op read` may ask for confirmation (Touch ID) each time the assistant starts, because the server reads the token at start.
- Pin the server version with `MCP_GRAFANA_VERSION` (default in the script); check the release notes before raising it.
- Revoke access: delete the token or the service account in Grafana, then `claude mcp remove grafana-u5g --scope local`.
