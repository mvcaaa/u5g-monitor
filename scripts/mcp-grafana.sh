#!/bin/bash
# Read-only Grafana MCP server (stdio) so an AI assistant can query metrics, dashboards and alert state. See docs/MCP.md.
# env: GRAFANA_URL (required); token in GRAFANA_SERVICE_ACCOUNT_TOKEN, or a 1Password reference in GRAFANA_TOKEN_OP_REF read at start.
set -e
: "${GRAFANA_URL:?set GRAFANA_URL}"
if [ -z "$GRAFANA_SERVICE_ACCOUNT_TOKEN" ]; then
  GRAFANA_SERVICE_ACCOUNT_TOKEN=$(op read "${GRAFANA_TOKEN_OP_REF:?set GRAFANA_SERVICE_ACCOUNT_TOKEN or GRAFANA_TOKEN_OP_REF}")
fi
export GRAFANA_URL GRAFANA_SERVICE_ACCOUNT_TOKEN
exec uvx "mcp-grafana@${MCP_GRAFANA_VERSION:-2.0.2}" -t stdio --disable-write \
  --enabled-tools search,datasource,prometheus,alerting,dashboard,folder,annotations
