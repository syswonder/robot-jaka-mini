#!/usr/bin/env bash
# One-time host setup for the dockerless deployment:
#   1. ros-humble-robot-state-publisher (robot_description native mode)
#   2. systemd-owned Zenoh router (rmw_zenohd) on tcp/127.0.0.1:7447
# After this, boot with plain `rbnx boot` (from a shell that has sourced
# .vlmkey) or `bash start.sh` — both reuse the systemd router.
#
# Run with sudo in a real terminal:   sudo bash setup-native-boot.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run with sudo" >&2; exit 1; }
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[setup] installing ros-humble-robot-state-publisher (robot_description native)"
apt-get install -y ros-humble-robot-state-publisher

echo "[setup] installing rbnx-zenoh-router systemd service"
cp "$DEPLOY_DIR/rbnx-zenoh-router.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable rbnx-zenoh-router
# If a start.sh-owned router currently holds 7447, the unit keeps retrying
# (StartLimitIntervalSec=0) and binds as soon as the port frees.
systemctl restart rbnx-zenoh-router || true
sleep 1
systemctl --no-pager --lines=5 status rbnx-zenoh-router || true

echo
echo "[setup] done. Reboot the stack with either:"
echo "  bash start.sh                     # from any shell"
echo "  source .vlmkey && rbnx boot       # bare boot (or add .vlmkey to ~/.zshrc)"
