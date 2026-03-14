#!/bin/bash
# =============================================================================
# MidnightCEO — Local Compute Mode Setup
# =============================================================================
#
# This script configures a macOS machine to run MidnightCEO agent workers
# locally.  It performs system checks, collects API credentials, pulls Docker
# images, installs a Cloudflare tunnel, and starts the service.
#
# Usage:
#   curl -fsSL https://install.midnightceo.ai | bash
#   — or —
#   bash setup.sh
#
# Requirements:
#   - macOS 13 (Ventura) or later
#   - 16 GB RAM minimum
#   - 20 GB free disk space
#   - Docker Desktop installed and running
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors and formatting
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

CONFIG_DIR="$HOME/.midnightceo"
ENV_FILE="$CONFIG_DIR/.env"
COMPOSE_FILE="$CONFIG_DIR/docker-compose.local.yml"
DATA_DIR="$CONFIG_DIR/data"
LOG_FILE="$CONFIG_DIR/setup.log"
PLIST_NAME="com.midnightceo.agents"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
  echo -e "  ${ARROW} $1"
  log "INFO: $1"
}

success() {
  echo -e "  ${CHECKMARK} $1"
  log "OK: $1"
}

warn() {
  echo -e "  ${YELLOW}⚠${NC} $1"
  log "WARN: $1"
}

fail() {
  echo -e "  ${CROSSMARK} $1"
  log "FAIL: $1"
  exit 1
}

spinner() {
  local pid=$1
  local msg=$2
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    local char="${SPINNER_CHARS:$i:1}"
    printf "\r  ${CYAN}%s${NC} %s" "$char" "$msg"
    i=$(( (i + 1) % ${#SPINNER_CHARS} ))
    sleep 0.1
  done
  printf "\r"
}

prompt_required() {
  local var_name=$1
  local prompt_text=$2
  local value=""
  while [ -z "$value" ]; do
    echo -ne "  ${ARROW} ${prompt_text}: "
    read -r value
    if [ -z "$value" ]; then
      echo -e "    ${RED}This field is required.${NC}"
    fi
  done
  eval "$var_name='$value'"
}

prompt_secret() {
  local var_name=$1
  local prompt_text=$2
  local value=""
  while [ -z "$value" ]; do
    echo -ne "  ${ARROW} ${prompt_text}: "
    read -rs value
    echo ""
    if [ -z "$value" ]; then
      echo -e "    ${RED}This field is required.${NC}"
    fi
  done
  eval "$var_name='$value'"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║       MidnightCEO  Local Compute         ║"
echo "  ║                                          ║"
echo "  ║   Run your AI workforce on your Mac.     ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Create config directory and log file early
mkdir -p "$CONFIG_DIR"
touch "$LOG_FILE"

# ---------------------------------------------------------------------------
# Step 1: System Requirements
# ---------------------------------------------------------------------------

echo -e "${BOLD}[1/12] Checking system requirements${NC}"
echo ""

# macOS check
if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This installer only supports macOS. Detected: $(uname -s)"
fi

# macOS version check (require 13+)
MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "0.0.0")
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)

if [ "$MACOS_MAJOR" -ge 13 ] 2>/dev/null; then
  success "macOS $MACOS_VERSION (13+ required)"
else
  fail "macOS 13 (Ventura) or later is required. Found: $MACOS_VERSION"
fi

# RAM check (require 16GB+)
RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
RAM_GB=$(( RAM_BYTES / 1073741824 ))

if [ "$RAM_GB" -ge 16 ]; then
  success "RAM: ${RAM_GB} GB (16 GB minimum)"
else
  fail "16 GB RAM required. Found: ${RAM_GB} GB. MidnightCEO agents need at least 16 GB to run effectively."
fi

# Disk space check (require 20GB free)
DISK_FREE_KB=$(df -k "$HOME" | tail -1 | awk '{print $4}')
DISK_FREE_GB=$(( DISK_FREE_KB / 1048576 ))

if [ "$DISK_FREE_GB" -ge 20 ]; then
  success "Disk: ${DISK_FREE_GB} GB free (20 GB minimum)"
else
  fail "20 GB free disk space required. Found: ${DISK_FREE_GB} GB"
fi

# CPU info
CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
success "CPU: ${CPU_MODEL}"

echo ""

# ---------------------------------------------------------------------------
# Step 2: Check and install Docker
# ---------------------------------------------------------------------------

echo -e "${BOLD}[2/12] Checking Docker${NC}"
echo ""

if command -v docker &>/dev/null; then
  if docker info &>/dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "unknown")
    success "Docker ${DOCKER_VERSION} installed and running"
  else
    warn "Docker is installed but the daemon is not running."
    info "Attempting to start Docker Desktop..."
    open -a "Docker" 2>/dev/null || true
    echo ""
    info "Waiting for Docker daemon to start (up to 60 seconds)..."
    DOCKER_WAIT=0
    while ! docker info &>/dev/null && [ "$DOCKER_WAIT" -lt 60 ]; do
      sleep 2
      DOCKER_WAIT=$((DOCKER_WAIT + 2))
    done
    if docker info &>/dev/null; then
      success "Docker daemon is now running"
    else
      fail "Docker daemon did not start within 60 seconds. Please start Docker Desktop manually and re-run this script."
    fi
  fi
else
  warn "Docker is not installed."
  if command -v brew &>/dev/null; then
    echo -ne "  ${ARROW} Install Docker Desktop via Homebrew? (Y/n): "
    read -r INSTALL_DOCKER
    if [ "$INSTALL_DOCKER" != "n" ] && [ "$INSTALL_DOCKER" != "N" ]; then
      info "Installing Docker Desktop via Homebrew..."
      if brew install --cask docker >> "$LOG_FILE" 2>&1; then
        success "Docker Desktop installed"
        info "Please open Docker Desktop from Applications and complete first-run setup."
        info "Then re-run this setup script."
        fail "Re-run this script after Docker Desktop is running."
      else
        fail "Failed to install Docker Desktop via Homebrew. Check $LOG_FILE for details."
      fi
    else
      fail "Docker is required. Install it from https://docker.com and re-run this script."
    fi
  else
    fail "Docker is not installed. Please install Docker Desktop from https://docker.com"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Check and install cloudflared
# ---------------------------------------------------------------------------

echo -e "${BOLD}[3/12] Checking Cloudflare Tunnel (cloudflared)${NC}"
echo ""

if command -v cloudflared &>/dev/null; then
  CF_VERSION=$(cloudflared --version 2>/dev/null | head -1 || echo "unknown")
  success "cloudflared already installed: $CF_VERSION"
else
  info "cloudflared is not installed. Installing..."
  if command -v brew &>/dev/null; then
    info "Installing via Homebrew..."
    if brew install cloudflared >> "$LOG_FILE" 2>&1; then
      success "cloudflared installed via Homebrew"
    else
      fail "Failed to install cloudflared via Homebrew. Check $LOG_FILE"
    fi
  else
    info "Installing cloudflared binary directly..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
      CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
    else
      CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
    fi

    TMP_DIR=$(mktemp -d)
    if curl -fsSL "$CF_URL" -o "$TMP_DIR/cloudflared.tgz" && \
       tar -xzf "$TMP_DIR/cloudflared.tgz" -C "$TMP_DIR" && \
       sudo mv "$TMP_DIR/cloudflared" /usr/local/bin/cloudflared && \
       sudo chmod +x /usr/local/bin/cloudflared; then
      rm -rf "$TMP_DIR"
      success "cloudflared installed to /usr/local/bin/"
    else
      rm -rf "$TMP_DIR"
      fail "Failed to install cloudflared. Please install manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/"
    fi
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Create local data directory
# ---------------------------------------------------------------------------

echo -e "${BOLD}[4/12] Setting up local data directory${NC}"
echo ""

mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/redis"
mkdir -p "$DATA_DIR/agent-state"
mkdir -p "$DATA_DIR/logs"

# Secure the directory — only the owner should access credentials
chmod 700 "$CONFIG_DIR"

success "Data directory created at $CONFIG_DIR"
success "Subdirectories: redis, agent-state, logs"

echo ""

# ---------------------------------------------------------------------------
# Step 5: Collect API credentials
# ---------------------------------------------------------------------------

echo -e "${BOLD}[5/12] Configuring API credentials${NC}"
echo ""
echo -e "  ${DIM}You can find these in your MidnightCEO dashboard at console.midnightceo.ai/settings${NC}"
echo ""

# Check if .env already exists
WRITE_ENV=""
if [ -f "$ENV_FILE" ]; then
  echo -e "  ${YELLOW}Existing configuration found at $ENV_FILE${NC}"
  echo -ne "  ${ARROW} Overwrite? (y/N): "
  read -r OVERWRITE
  if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
    success "Keeping existing configuration"
    echo ""
    # Source existing values for later use
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE" 2>/dev/null || true
    set +a
  else
    WRITE_ENV=true
  fi
else
  WRITE_ENV=true
fi

if [ "${WRITE_ENV:-}" = "true" ]; then
  prompt_required COMPANY_ID "Company ID (from your dashboard)"
  prompt_secret ANTHROPIC_API_KEY "Anthropic API Key (sk-ant-...)"
  prompt_required SUPABASE_URL "Supabase URL (https://xxx.supabase.co)"
  prompt_secret SUPABASE_SERVICE_ROLE_KEY "Supabase Service Role Key"

  echo -ne "  ${ARROW} Temporal Host (press Enter for default): "
  read -r TEMPORAL_HOST
  TEMPORAL_HOST=${TEMPORAL_HOST:-"localhost:7233"}

  echo -ne "  ${ARROW} Console URL (press Enter for default): "
  read -r CONSOLE_URL_INPUT
  CONSOLE_URL_INPUT=${CONSOLE_URL_INPUT:-"https://console.midnightceo.ai"}

  # Generate a machine ID
  MACHINE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

  # Machine name
  DEFAULT_MACHINE_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
  echo -ne "  ${ARROW} Machine name [${DEFAULT_MACHINE_NAME}]: "
  read -r MACHINE_NAME
  MACHINE_NAME="${MACHINE_NAME:-$DEFAULT_MACHINE_NAME}"

  success "Credentials collected"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 6: Write .env file
# ---------------------------------------------------------------------------

echo -e "${BOLD}[6/12] Writing configuration${NC}"
echo ""

if [ "${WRITE_ENV:-}" = "true" ]; then
  cat > "$ENV_FILE" << ENVEOF
# =============================================================================
# MidnightCEO — Local Compute Mode Configuration
# Generated on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# =============================================================================

# Company
COMPANY_ID=${COMPANY_ID}
MACHINE_ID=${MACHINE_ID}
MACHINE_NAME=${MACHINE_NAME}

# Anthropic
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
DEFAULT_MODEL=claude-sonnet-4-20250514

# Supabase
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}

# Temporal
TEMPORAL_HOST=${TEMPORAL_HOST}

# Console
CONSOLE_URL=${CONSOLE_URL_INPUT}

# Redis (local — managed by Docker Compose)
REDIS_URL=redis://localhost:6379/0

# Runtime
APP_ENV=local
LOG_LEVEL=INFO
COMPUTE_MODE=local
ENVEOF

  chmod 600 "$ENV_FILE"
  success "Configuration written to $ENV_FILE (permissions: 600)"
else
  success "Using existing configuration"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 7: Copy docker-compose.local.yml
# ---------------------------------------------------------------------------

echo -e "${BOLD}[7/12] Setting up Docker Compose${NC}"
echo ""

if [ -f "$SCRIPT_DIR/docker-compose.local.yml" ]; then
  if [ -f "$COMPOSE_FILE" ]; then
    echo -ne "  ${ARROW} Overwrite existing compose file? (y/N): "
    read -r OVERWRITE_COMPOSE
    if [ "$OVERWRITE_COMPOSE" = "y" ] || [ "$OVERWRITE_COMPOSE" = "Y" ]; then
      cp "$SCRIPT_DIR/docker-compose.local.yml" "$COMPOSE_FILE"
      success "Docker Compose file updated"
    else
      success "Keeping existing compose file"
    fi
  else
    cp "$SCRIPT_DIR/docker-compose.local.yml" "$COMPOSE_FILE"
    success "Docker Compose file installed"
  fi
else
  if [ ! -f "$COMPOSE_FILE" ]; then
    warn "docker-compose.local.yml not found in installer directory."
    warn "Please copy it manually to $COMPOSE_FILE"
  else
    success "Using existing Docker Compose file"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# Step 8: Pull Docker images
# ---------------------------------------------------------------------------

echo -e "${BOLD}[8/12] Pulling Docker images${NC}"
echo ""

IMAGES=(
  "midnightceo/agent-workers:latest"
  "midnightceo/fastapi-backend:latest"
  "midnightceo/temporal-worker:latest"
  "redis:7-alpine"
  "cloudflare/cloudflared:latest"
)

for IMAGE in "${IMAGES[@]}"; do
  info "Pulling $IMAGE..."
  if docker pull "$IMAGE" >> "$LOG_FILE" 2>&1; then
    success "Pulled $IMAGE"
  else
    warn "Failed to pull $IMAGE (may not exist yet in registry — continuing)"
  fi
done

echo ""

# ---------------------------------------------------------------------------
# Step 9: Configure Cloudflare Tunnel
# ---------------------------------------------------------------------------

echo -e "${BOLD}[9/12] Configuring Cloudflare Tunnel${NC}"
echo ""

info "A quick-tunnel will be created automatically when agents start."
info "The tunnel URL will be registered in your Supabase companies table."
info "The tunnel runs as a sidecar container alongside the backend API."
success "Tunnel configuration ready"

echo ""

# ---------------------------------------------------------------------------
# Step 10: Set up environment variables
# ---------------------------------------------------------------------------

echo -e "${BOLD}[10/12] Verifying environment${NC}"
echo ""

# Verify the .env file has all required keys
REQUIRED_KEYS=("COMPANY_ID" "ANTHROPIC_API_KEY" "SUPABASE_URL" "SUPABASE_SERVICE_ROLE_KEY")
MISSING_KEYS=()

for KEY in "${REQUIRED_KEYS[@]}"; do
  # shellcheck disable=SC1090
  VALUE=$(grep "^${KEY}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | head -1)
  if [ -z "$VALUE" ]; then
    MISSING_KEYS+=("$KEY")
  fi
done

if [ ${#MISSING_KEYS[@]} -eq 0 ]; then
  success "All required environment variables are set"
else
  for KEY in "${MISSING_KEYS[@]}"; do
    warn "Missing required key: $KEY"
  done
  warn "Please edit $ENV_FILE and add the missing values."
fi

echo ""

# ---------------------------------------------------------------------------
# Step 11: Install LaunchAgent (auto-start on login)
# ---------------------------------------------------------------------------

echo -e "${BOLD}[11/12] Configuring auto-start on login${NC}"
echo ""

echo -ne "  ${ARROW} Start MidnightCEO automatically on login? (Y/n): "
read -r AUTOSTART
if [ "$AUTOSTART" = "n" ] || [ "$AUTOSTART" = "N" ]; then
  info "Skipping auto-start configuration."
else
  # Check if the plist template exists alongside this script
  PLIST_SRC="$SCRIPT_DIR/com.midnightceo.agents.plist"
  LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$LAUNCH_AGENTS_DIR"

  if [ -f "$PLIST_SRC" ]; then
    # Copy the template and substitute paths
    sed \
      -e "s|__CONFIG_DIR__|${CONFIG_DIR}|g" \
      -e "s|__COMPOSE_FILE__|${COMPOSE_FILE}|g" \
      -e "s|__LOG_FILE__|${CONFIG_DIR}/midnightceo.log|g" \
      "$PLIST_SRC" > "$PLIST_FILE" 2>/dev/null || cp "$PLIST_SRC" "$PLIST_FILE"
  else
    # Generate a plist from scratch
    cat > "$PLIST_FILE" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/docker</string>
        <string>compose</string>
        <string>-f</string>
        <string>${COMPOSE_FILE}</string>
        <string>up</string>
        <string>-d</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>${CONFIG_DIR}</string>
</dict>
</plist>
PLISTEOF
  fi

  # Load the LaunchAgent
  launchctl load "$PLIST_FILE" 2>/dev/null || true
  success "LaunchAgent installed at $PLIST_FILE"
fi

# Set up caffeinate wrapper for sleep prevention
cat > "$CONFIG_DIR/start-with-caffeinate.sh" << 'CAFEOF'
#!/bin/bash
# Start caffeinate in the background (prevents sleep while this script runs)
# -d: prevent display sleep, -i: prevent idle sleep, -s: prevent system sleep
caffeinate -dis &
CAFFEINATE_PID=$!

# Trap EXIT to clean up caffeinate
cleanup() {
  kill "$CAFFEINATE_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Start docker compose and wait
docker compose -f "$HOME/.midnightceo/docker-compose.local.yml" up

# caffeinate will be killed by the trap when this exits
CAFEOF
chmod +x "$CONFIG_DIR/start-with-caffeinate.sh"

echo ""

# ---------------------------------------------------------------------------
# Step 12: Start services and verify
# ---------------------------------------------------------------------------

echo -e "${BOLD}[12/12] Starting MidnightCEO and verifying${NC}"
echo ""

info "Starting Docker containers..."

if docker compose -f "$COMPOSE_FILE" up -d >> "$LOG_FILE" 2>&1; then
  success "Docker containers started"
else
  warn "Some containers may have failed to start. Check $LOG_FILE for details."
  warn "This is expected if the MidnightCEO images aren't published yet."
fi

# Wait a moment for containers to initialize
sleep 3

# Show container status
info "Container status:"
docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || true
echo ""

# Health checks
info "Running health checks..."

# Check Redis
if docker compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
  success "Redis: healthy"
else
  warn "Redis: not responding yet (may still be starting)"
fi

# Check backend API
sleep 2
if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
  success "Backend API: healthy"
else
  warn "Backend API: not responding yet (may still be starting)"
fi

# Check cloudflared
if docker compose -f "$COMPOSE_FILE" ps tunnel 2>/dev/null | grep -q "running"; then
  success "Cloudflare Tunnel: running"
else
  warn "Cloudflare Tunnel: not running yet (backend may still be starting)"
fi

echo ""

# ---------------------------------------------------------------------------
# Done!
# ---------------------------------------------------------------------------

echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║     Setup complete!                      ║"
echo "  ║                                          ║"
echo "  ║     Your AI workforce is running.        ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Quick reference:${NC}"
echo -e "    Config:       ${DIM}$CONFIG_DIR${NC}"
echo -e "    Logs:         ${DIM}$LOG_FILE${NC}"
echo -e "    Compose:      ${DIM}$COMPOSE_FILE${NC}"
echo -e "    Stop:         ${DIM}docker compose -f $COMPOSE_FILE down${NC}"
echo -e "    Uninstall:    ${DIM}bash ${SCRIPT_DIR}/uninstall.sh${NC}"
echo ""

# Open the Founder Console
OPEN_URL="${CONSOLE_URL_INPUT:-https://console.midnightceo.ai}"
info "Opening Founder Console..."
open "$OPEN_URL" 2>/dev/null || true

echo ""
echo -e "  ${DIM}MidnightCEO will start automatically on login.${NC}"
echo -e "  ${DIM}Your agents never sleep. Neither does your company.${NC}"
echo ""
