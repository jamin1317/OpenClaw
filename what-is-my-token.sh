#!/usr/bin/env bash
set -euo pipefail

if [ -n "${SUDO_USER:-}" ]; then
    OPENCLAW_HOME="$(eval echo "~$SUDO_USER")/.openclaw"
else
    OPENCLAW_HOME="$HOME/.openclaw"
fi

CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "OpenClaw config not found at $CONFIG_FILE"
    exit 1
fi

TOKEN=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['gateway']['auth']['token'])")
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_VM_IP")

echo ""
echo "Gateway Token: $TOKEN"
echo ""
echo "Open this URL in your browser to connect:"
echo "  https://$HOST_IP/openclaw/?token=$TOKEN"
echo ""
echo "If openclaw shows an error about pairing run"
echo "sudo ~/OpenClaw/approve-pairing.sh"
echo ""
