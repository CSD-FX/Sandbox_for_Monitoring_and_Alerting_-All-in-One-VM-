#!/usr/bin/env bash
set -euo pipefail
if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/uninstall.sh" >&2
  exit 1
fi

systemctl disable --now prometheus || true
systemctl disable --now node_exporter || true
systemctl disable --now alertmanager || true
systemctl disable --now grafana-server || true

rm -f /etc/systemd/system/prometheus.service
rm -f /etc/systemd/system/node_exporter.service
rm -f /etc/systemd/system/alertmanager.service
systemctl daemon-reload

rm -rf /etc/prometheus /var/lib/prometheus
rm -rf /etc/alertmanager /var/lib/alertmanager
rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
rm -f /usr/local/bin/node_exporter
rm -f /usr/local/bin/alertmanager /usr/local/bin/amtool

userdel prometheus 2>/dev/null || true
userdel node_exporter 2>/dev/null || true
userdel alertmanager 2>/dev/null || true

apt-get purge -y grafana || true
rm -f /etc/apt/sources.list.d/grafana.list
rm -f /etc/apt/keyrings/grafana.gpg
apt-get update -y || true

echo "Uninstall complete."
