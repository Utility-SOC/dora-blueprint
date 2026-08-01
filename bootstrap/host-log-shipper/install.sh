#!/usr/bin/env bash
# Installs the appserv host-level log shipper -- see this directory's config.alloy for why it
# exists (the in-cluster Alloy DaemonSet can't see appserv's own host logs). Idempotent.
#
# Prerequisites this script assumes, not automates (real one-time setup already done):
#   - the `alloy` binary at /usr/local/bin/alloy (downloaded from
#     https://github.com/grafana/alloy/releases -- no apt repo added for a single binary)
#   - svc_bob in the `adm` group (least-privilege read access to auth.log/syslog, which are
#     root:adm 0640 -- not running this as root)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$REPO_ROOT/bootstrap/host-log-shipper"

sudo mkdir -p /etc/alloy-host /var/lib/alloy-host
sudo cp "$SRC_DIR/config.alloy" /etc/alloy-host/config.alloy
sudo chown -R svc_bob:svc_bob /var/lib/alloy-host
sudo cp "$SRC_DIR/alloy-host.service" /etc/systemd/system/alloy-host.service

sudo systemctl daemon-reload
sudo systemctl enable --now alloy-host.service

echo
echo "==> status"
sudo systemctl status --no-pager alloy-host.service | grep -E "^●|Active:"
