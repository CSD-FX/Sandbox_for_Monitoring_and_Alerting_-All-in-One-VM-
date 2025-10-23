#!/usr/bin/env bash
set -euo pipefail
services=(prometheus node_exporter alertmanager grafana-server)
for s in "${services[@]}"; do
  echo "==> $s"
  systemctl --no-pager -l status "$s" | sed -n '1,12p' || true
  echo
done

echo "Ports: 9090 (Prometheus), 9093 (Alertmanager), 3000 (Grafana), 9100 (Node Exporter)"
