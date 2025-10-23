#!/usr/bin/env bash
set -euo pipefail

# Versions can be overridden via environment variables
PROM_VERSION=${PROM_VERSION:-2.53.1}
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION:-1.8.1}
ALERTMANAGER_VERSION=${ALERTMANAGER_VERSION:-0.27.0}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/install.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget tar unzip jq adduser apt-transport-https software-properties-common gnupg

# Create users if not exist
id -u prometheus >/dev/null 2>&1 || useradd --no-create-home --shell /usr/sbin/nologin prometheus
id -u node_exporter >/dev/null 2>&1 || useradd --no-create-home --shell /usr/sbin/nologin node_exporter
id -u alertmanager >/dev/null 2>&1 || useradd --no-create-home --shell /usr/sbin/nologin alertmanager

# Directories
install -d -o prometheus -g prometheus /etc/prometheus /var/lib/prometheus /etc/prometheus/rules
install -d -o alertmanager -g alertmanager /etc/alertmanager /var/lib/alertmanager

# Install Prometheus
cd /tmp
curl -fsSLO https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
rm -rf prometheus-${PROM_VERSION}.linux-amd64
tar -xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
cd prometheus-${PROM_VERSION}.linux-amd64
install -m 0755 prometheus /usr/local/bin/prometheus
install -m 0755 promtool /usr/local/bin/promtool
install -m 0644 consoles/* -D -t /etc/prometheus/consoles
install -m 0644 console_libraries/* -D -t /etc/prometheus/console_libraries
cd /tmp

# Prometheus config
install -m 0644 "$ROOT_DIR/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
install -m 0644 "$ROOT_DIR/prometheus/rules/alerts.yml" /etc/prometheus/rules/alerts.yml
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Install Node Exporter
cd /tmp
curl -fsSLO https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64
tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
install -m 0755 node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter

# Install Alertmanager
cd /tmp
curl -fsSLO https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
rm -rf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64
tar -xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
install -m 0755 alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/alertmanager
install -m 0755 alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool /usr/local/bin/amtool
install -m 0644 "$ROOT_DIR/alertmanager/alertmanager.yml" /etc/alertmanager/alertmanager.yml
chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

# Systemd units
cat >/etc/systemd/system/prometheus.service <<'UNIT'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/alertmanager.service <<'UNIT'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=0.0.0.0:9093
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

# Grafana (apt repo)
mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
chmod 0644 /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" >/etc/apt/sources.list.d/grafana.list
apt-get update -y
apt-get install -y grafana

# Enable and start all
systemctl enable --now node_exporter
systemctl enable --now prometheus
systemctl enable --now alertmanager
systemctl enable --now grafana-server

# Health checks
sleep 3
curl -fsS http://localhost:9090/-/healthy >/dev/null || true
curl -fsS http://localhost:9100/metrics >/dev/null || true
curl -fsS http://localhost:9093 >/dev/null || true
curl -fsS http://localhost:3000 >/dev/null || true

echo "Installation complete. Access UIs via your EC2 public IP: 9090, 9093, 3000, 9100"
