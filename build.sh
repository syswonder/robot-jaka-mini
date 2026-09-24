#!/usr/bin/env bash
# Deployment build entry: prepares a deployment-local venv (robonix_api deps
# + grpcio-tools for package codegen, with --system-site-packages so rclpy
# from the system ROS 2 install is visible), then builds the selected
# manifests. Keeps the system python3 untouched (JetPack tensorflow pins
# protobuf<5; robonix_api needs protobuf 6).
set -euo pipefail
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$DEPLOY_DIR/.venv"

if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv --system-site-packages "$VENV"
fi
"$VENV/bin/pip" install -q \
  grpcio==1.80.0 protobuf==6.33.6 "mcp>=1.27,<2" "fastmcp>=3,<5" pyyaml>=6 \
  grpcio-tools==1.76.0

# rbnx codegen inside fetched packages honors this interpreter override.
export RBNX_CODEGEN_PYTHON="$VENV/bin/python"
export PATH="$VENV/bin:$PATH"

SIBLINGS="$(dirname "$DEPLOY_DIR")"
rbnx build -p "$SIBLINGS/primitive-jaka-rbnx"
rbnx build -p "$SIBLINGS/primitive-orbbec-camera-rbnx"
rbnx build -p "$SIBLINGS/skill-jaka-rbnx"
rbnx build -f "$DEPLOY_DIR/robonix_manifest.yaml"
rbnx build -f "$DEPLOY_DIR/robonix_manifest.no-motion.yaml"
