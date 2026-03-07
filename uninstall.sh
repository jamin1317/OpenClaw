#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# OpenClaw Uninstall Script
# Stops containers, removes volumes, and cleans up all data.
# ------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)."
    exit 1
fi

# Determine the real user's home (not root's)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME="$(eval echo "~$SUDO_USER")"
else
    USER_HOME="$HOME"
fi

echo ""
echo -e "${YELLOW}This will remove all OpenClaw, Open WebUI, and Ollama containers, volumes, and data.${NC}"
echo ""
echo "  The following will be deleted:"
echo "    - All Docker containers and volumes created by this project"
echo "    - $USER_HOME/.openclaw/"
echo "    - $SCRIPT_DIR/.env"
echo "    - $SCRIPT_DIR/nginx/certs/"
echo ""
read -rp "Are you sure? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Aborted."
    exit 0
fi

# Stop and remove containers + volumes
if [ -f "$COMPOSE_FILE" ]; then
    log_info "Stopping and removing containers and volumes..."
    docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
else
    log_warn "docker-compose.yml not found, skipping container cleanup."
fi

# Remove OpenClaw data directory
if [ -d "$USER_HOME/.openclaw" ]; then
    log_info "Removing $USER_HOME/.openclaw/"
    rm -rf "$USER_HOME/.openclaw"
fi

# Remove generated .env
if [ -f "$SCRIPT_DIR/.env" ]; then
    log_info "Removing .env"
    rm -f "$SCRIPT_DIR/.env"
fi

# Remove nginx certs
if [ -d "$SCRIPT_DIR/nginx/certs" ]; then
    log_info "Removing nginx/certs/"
    rm -rf "$SCRIPT_DIR/nginx/certs"
fi

echo ""
log_info "Uninstall complete. The OpenClaw repo itself is still at $SCRIPT_DIR"
echo "  To fully remove, run: rm -rf $SCRIPT_DIR"
echo ""
