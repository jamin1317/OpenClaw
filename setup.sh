#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# OpenClaw Setup Script
# Installs Docker, configures environment, deploys OpenClaw +
# Open WebUI + Ollama + Nginx, and pulls an initial LLM.
# ------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${CYAN}"
    echo "  ___                    ____ _                "
    echo " / _ \ _ __   ___ _ __ / ___| | __ ___      __"
    echo "| | | | '_ \ / _ \ '_ \ |   | |/ _\` \ \ /\ / /"
    echo "| |_| | |_) |  __/ | | | |___| | (_| |\ V  V / "
    echo " \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/  "
    echo "      |_|                                       "
    echo -e "${NC}"
    echo "OpenClaw + Open WebUI + Ollama + Nginx"
    echo "Easy Home Lab AI Setup"
    echo "======================================="
    echo ""
}

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

# ------------------------------------------------------------------
# Install Docker and Docker Compose
# ------------------------------------------------------------------
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker is already installed: $(docker --version)"
    else
        log_info "Installing Docker..."
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg lsb-release

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
          | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        systemctl enable docker
        systemctl start docker
        log_info "Docker installed successfully."
    fi

    # Add the sudo user to the docker group if running via sudo
    if [ -n "${SUDO_USER:-}" ]; then
        if ! groups "$SUDO_USER" | grep -q '\bdocker\b'; then
            usermod -aG docker "$SUDO_USER"
            log_info "Added $SUDO_USER to the docker group (effective on next login)."
        fi
    fi
}

# ------------------------------------------------------------------
# Install additional packages
# ------------------------------------------------------------------
install_prerequisites() {
    log_info "Installing prerequisites..."
    apt-get update -y
    apt-get install -y curl git jq openssl
    log_info "Prerequisites installed."
}

# ------------------------------------------------------------------
# Prompt for configuration and write .env
# ------------------------------------------------------------------
configure_env() {
    echo ""
    echo -e "${CYAN}--- Configuration ---${NC}"
    echo ""

    # --- OpenClaw Gateway Token ---
    DEFAULT_GW_TOKEN=$(openssl rand -hex 32)
    echo "OpenClaw uses a gateway token to authenticate API requests."
    read -rp "OpenClaw Gateway Token [auto-generated]: " OPENCLAW_GATEWAY_TOKEN
    OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$DEFAULT_GW_TOKEN}"

    # --- OpenClaw Sandbox ---
    echo ""
    echo "Enable OpenClaw sandbox mode? (isolates agent execution)"
    read -rp "Enable sandbox? (y/N): " SANDBOX_CHOICE
    SANDBOX_CHOICE="${SANDBOX_CHOICE:-N}"
    if [[ "$SANDBOX_CHOICE" =~ ^[Yy] ]]; then
        OPENCLAW_SANDBOX="true"
    else
        OPENCLAW_SANDBOX="false"
    fi

    # --- Open WebUI Secret Key ---
    DEFAULT_SECRET=$(openssl rand -hex 32)
    echo ""
    echo "Open WebUI uses a secret key to sign session tokens."
    read -rp "WebUI Secret Key [auto-generated]: " WEBUI_SECRET_KEY
    WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$DEFAULT_SECRET}"

    # --- Open WebUI Authentication ---
    echo ""
    echo "Enable authentication for Open WebUI?"
    echo "  If enabled, users must create an account to use the UI."
    echo "  If disabled, anyone on your network can use it."
    read -rp "Enable authentication? (Y/n): " AUTH_CHOICE
    AUTH_CHOICE="${AUTH_CHOICE:-Y}"
    if [[ "$AUTH_CHOICE" =~ ^[Yy] ]]; then
        WEBUI_AUTH="true"
    else
        WEBUI_AUTH="false"
    fi

    # --- Model Selection ---
    echo ""
    echo "Choose an LLM to download into Ollama."
    echo "Popular options:"
    echo "  1) llama3.2       — Meta Llama 3.2 3B (2.0 GB) — great general purpose"
    echo "  2) llama3.2:1b    — Meta Llama 3.2 1B (1.3 GB) — lightweight"
    echo "  3) mistral        — Mistral 7B (4.1 GB) — strong all-around"
    echo "  4) codellama      — Code Llama 7B (3.8 GB) — optimized for code"
    echo "  5) tinyllama      — TinyLlama 1.1B (637 MB) — minimal resources"
    echo "  6) phi3           — Microsoft Phi-3 3.8B (2.3 GB) — compact & capable"
    echo "  7) custom         — Enter a model name manually"
    echo "  8) skip           — Don't download a model now"
    echo ""
    read -rp "Select a model [1]: " MODEL_CHOICE
    MODEL_CHOICE="${MODEL_CHOICE:-1}"

    case "$MODEL_CHOICE" in
        1) OLLAMA_MODEL="llama3.2" ;;
        2) OLLAMA_MODEL="llama3.2:1b" ;;
        3) OLLAMA_MODEL="mistral" ;;
        4) OLLAMA_MODEL="codellama" ;;
        5) OLLAMA_MODEL="tinyllama" ;;
        6) OLLAMA_MODEL="phi3" ;;
        7)
            read -rp "Enter the model name (e.g., gemma2:2b): " OLLAMA_MODEL
            if [ -z "$OLLAMA_MODEL" ]; then
                log_warn "No model specified, skipping download."
                OLLAMA_MODEL=""
            fi
            ;;
        8) OLLAMA_MODEL="" ;;
        *) OLLAMA_MODEL="llama3.2" ;;
    esac

    # --- Write .env file ---
    log_info "Writing configuration to $ENV_FILE"
    cat > "$ENV_FILE" <<EOF
# OpenClaw Configuration — generated by setup.sh
# Do NOT commit this file to version control.

# OpenClaw
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN
OPENCLAW_SANDBOX=$OPENCLAW_SANDBOX

# Open WebUI
WEBUI_SECRET_KEY=$WEBUI_SECRET_KEY
WEBUI_AUTH=$WEBUI_AUTH
EOF

    chmod 600 "$ENV_FILE"
    log_info "Configuration saved."
}

# ------------------------------------------------------------------
# Create certs directory
# ------------------------------------------------------------------
prepare_nginx() {
    mkdir -p "$SCRIPT_DIR/nginx/certs"
    log_info "Nginx configuration ready."
}

# ------------------------------------------------------------------
# Start containers
# ------------------------------------------------------------------
start_containers() {
    log_info "Pulling container images (this may take a few minutes)..."
    docker compose -f "$COMPOSE_FILE" pull

    log_info "Starting containers..."
    docker compose -f "$COMPOSE_FILE" up -d

    log_info "Waiting for containers to start..."
    sleep 10

    # Verify all containers are running
    RUNNING=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null | jq -r '.State' 2>/dev/null | grep -c "running" || true)
    if [ "$RUNNING" -ge 4 ]; then
        log_info "All 4 containers are running."
    else
        log_warn "Some containers may not be running yet. Check with: docker compose ps"
        docker compose -f "$COMPOSE_FILE" ps
    fi
}

# ------------------------------------------------------------------
# Pull the selected LLM into Ollama
# ------------------------------------------------------------------
onboard_model() {
    if [ -z "${OLLAMA_MODEL:-}" ]; then
        log_info "No model selected — skipping download."
        return
    fi

    log_info "Pulling model '$OLLAMA_MODEL' into Ollama..."
    log_info "This may take a while depending on model size and internet speed."

    # Wait for Ollama to be ready
    RETRIES=0
    MAX_RETRIES=30
    until docker compose -f "$COMPOSE_FILE" exec ollama ollama list &>/dev/null; do
        RETRIES=$((RETRIES + 1))
        if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
            log_error "Ollama did not become ready in time. You can pull the model later with:"
            echo "  sudo docker compose exec ollama ollama pull $OLLAMA_MODEL"
            return
        fi
        sleep 2
    done

    docker compose -f "$COMPOSE_FILE" exec ollama ollama pull "$OLLAMA_MODEL"
    log_info "Model '$OLLAMA_MODEL' is ready."
}

# ------------------------------------------------------------------
# Print summary
# ------------------------------------------------------------------
print_summary() {
    # Detect the host IP
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_VM_IP")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  OpenClaw setup complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  Open WebUI:      ${CYAN}http://$HOST_IP${NC}"
    echo -e "  OpenClaw Gateway: ${CYAN}http://$HOST_IP/openclaw/${NC}"
    echo -e "  Ollama API:      ${CYAN}http://$HOST_IP/ollama/${NC}"
    echo ""
    if [ "${WEBUI_AUTH}" = "true" ]; then
        echo "  Create your admin account on first visit to Open WebUI."
    else
        echo "  Open WebUI authentication is disabled — anyone on your network can use it."
    fi
    echo ""
    echo -e "  OpenClaw Gateway Token: ${CYAN}$OPENCLAW_GATEWAY_TOKEN${NC}"
    echo "  (saved in .env — use this to authenticate with the OpenClaw gateway)"
    echo ""
    if [ -n "${OLLAMA_MODEL:-}" ]; then
        echo -e "  Loaded model: ${CYAN}$OLLAMA_MODEL${NC}"
    fi
    echo ""
    echo "  Useful commands:"
    echo "    sudo docker compose ps          — check container status"
    echo "    sudo docker compose logs -f     — view logs"
    echo "    sudo docker compose down        — stop all containers"
    echo "    sudo docker compose up -d       — start all containers"
    echo ""
    echo "  Pull more models:"
    echo "    sudo docker compose exec ollama ollama pull mistral"
    echo ""
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
    print_banner
    check_root
    install_prerequisites
    install_docker
    configure_env
    prepare_nginx
    start_containers
    onboard_model
    print_summary
}

main "$@"
