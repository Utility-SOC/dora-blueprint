#!/usr/bin/env bash
# Installs/updates the systemd-supervised LAN port-forwards -- see README.md in this
# directory for why these exist (a bare `kubectl port-forward` has no reconnect logic
# and silently stays dead after its target pod restarts). Idempotent: safe to re-run
# any time a unit file here changes, or just to confirm everything's still running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNIT_DIR="$REPO_ROOT/bootstrap/port-forwards"
UNITS=(argocd hubble-ui grafana keycloak minio-console glpi loki-gateway lam)

for name in "${UNITS[@]}"; do
  sudo cp "$UNIT_DIR/$name.service" "/etc/systemd/system/platform-port-forward-$name.service"
done

sudo systemctl daemon-reload

for name in "${UNITS[@]}"; do
  sudo systemctl enable --now "platform-port-forward-$name.service"
done

echo
echo "==> status"
sudo systemctl status --no-pager "platform-port-forward-"*.service 2>&1 | grep -E "^●|Active:"
