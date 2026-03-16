#!/usr/bin/env bash
# =============================================================================
# MidnightCEO — Local Compute Mode Installer for macOS
#
# Turns a founder's MacBook into the agent compute backend while keeping
# the database, web frontend, and monitoring in the cloud.
#
# Usage:
#   curl -fsSL https://install.midnightceo.ai | bash
#   # or
#   ./install.sh [--dev]
#
# Flags:
#   --dev   Build Docker images from local source instead of pulling from registry
#
# This script is idempotent — safe to run multiple times.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

readonly MCE_DIR="$HOME/.midnightceo"
readonly MCE_LOG_DIR="$MCE_DIR/logs"
readonly MCE_STATE_DIR="$MCE_DIR/state"
readonly MCE_ENV_FILE="$MCE_DIR/.env"
readonly MCE_COMPOSE_FILE="$MCE_DIR/docker-compose.local.yml"
readonly MCE_VENV_DIR="$MCE_DIR/menubar-venv"
readonly MCE_CLI_PATH="/usr/local/bin/midnightceo"
readonly MCE_PLIST_LABEL="com.midnightceo.local"
readonly MCE_PLIST_PATH="$HOME/Library/LaunchAgents/${MCE_PLIST_LABEL}.plist"
readonly MCE_MENUBAR_APP="$MCE_DIR/menubar/app.py"

readonly INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"

DEV_MODE=false

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

info()    { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}${CYAN}==> %s${NC}\n" "$*"; }

die() {
    error "$@"
    exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dev)
                DEV_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--dev]"
                echo "  --dev  Build Docker images from local source"
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 1. System requirements
# ---------------------------------------------------------------------------

check_system_requirements() {
    header "Checking system requirements"

    # macOS version >= 13 (Ventura)
    local macos_version
    macos_version="$(sw_vers -productVersion 2>/dev/null || echo "0.0")"
    local major_version
    major_version="$(echo "$macos_version" | cut -d. -f1)"

    if [[ "$major_version" -lt 13 ]]; then
        die "macOS 13 (Ventura) or later is required. Found: $macos_version"
    fi
    success "macOS $macos_version (>= 13)"

    # RAM >= 16GB
    local ram_bytes
    ram_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    local ram_gb
    ram_gb=$(( ram_bytes / 1073741824 ))

    if [[ "$ram_gb" -lt 16 ]]; then
        die "16GB RAM minimum required. Found: ${ram_gb}GB"
    fi
    success "${ram_gb}GB RAM (>= 16GB)"

    # Docker installed and running
    if ! command -v docker &>/dev/null; then
        die "Docker is not installed. Please install Docker Desktop from https://docker.com/products/docker-desktop"
    fi

    if ! docker info &>/dev/null; then
        die "Docker is installed but not running. Please start Docker Desktop and try again."
    fi
    success "Docker is installed and running"

    # 20GB free disk space
    local free_space_kb
    free_space_kb="$(df -k "$HOME" | tail -1 | awk '{print $4}')"
    local free_space_gb
    free_space_gb=$(( free_space_kb / 1048576 ))

    if [[ "$free_space_gb" -lt 20 ]]; then
        die "20GB free disk space required. Found: ${free_space_gb}GB"
    fi
    success "${free_space_gb}GB free disk space (>= 20GB)"
}

# ---------------------------------------------------------------------------
# 2. Create directory structure
# ---------------------------------------------------------------------------

create_midnightceo_dir() {
    header "Creating MidnightCEO directory"

    mkdir -p "$MCE_LOG_DIR"
    mkdir -p "$MCE_STATE_DIR"
    mkdir -p "$MCE_DIR/menubar"

    success "Created $MCE_DIR"
}

# ---------------------------------------------------------------------------
# 3. Collect credentials and write .env
# ---------------------------------------------------------------------------

collect_credentials() {
    header "Configuring environment"

    # If .env already exists, ask whether to reconfigure
    if [[ -f "$MCE_ENV_FILE" ]]; then
        warn "Existing configuration found at $MCE_ENV_FILE"
        printf "  Reconfigure? [y/N] "
        read -r reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            info "Keeping existing configuration"
            return 0
        fi
    fi

    # Detect machine name
    local machine_name
    machine_name="$(scutil --get ComputerName 2>/dev/null || hostname -s)"

    # Generate a machine ID
    local machine_id
    machine_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

    echo ""
    info "Enter your credentials (these stay local and are never sent to MidnightCEO servers)."
    echo ""

    # Anthropic API Key
    local anthropic_key=""
    while [[ -z "$anthropic_key" ]]; do
        printf "  Anthropic API Key: "
        read -r anthropic_key
        if [[ -z "$anthropic_key" ]]; then
            warn "Anthropic API Key is required."
        fi
    done

    # Supabase URL
    local supabase_url=""
    while [[ -z "$supabase_url" ]]; do
        printf "  Supabase URL (e.g. https://abc.supabase.co): "
        read -r supabase_url
        if [[ -z "$supabase_url" ]]; then
            warn "Supabase URL is required."
        fi
    done

    # Supabase Service Role Key
    local supabase_key=""
    while [[ -z "$supabase_key" ]]; do
        printf "  Supabase Service Role Key: "
        read -r supabase_key
        if [[ -z "$supabase_key" ]]; then
            warn "Supabase Service Role Key is required."
        fi
    done

    # Company ID
    local company_id=""
    while [[ -z "$company_id" ]]; do
        printf "  Company ID (from your MidnightCEO dashboard): "
        read -r company_id
        if [[ -z "$company_id" ]]; then
            warn "Company ID is required."
        fi
    done

    # Write .env from template
    info "Writing configuration to $MCE_ENV_FILE"

    if [[ -f "$INSTALLER_DIR/.env.template" ]]; then
        sed \
            -e "s|__ANTHROPIC_API_KEY__|${anthropic_key}|g" \
            -e "s|__SUPABASE_URL__|${supabase_url}|g" \
            -e "s|__SUPABASE_SERVICE_ROLE_KEY__|${supabase_key}|g" \
            -e "s|__COMPANY_ID__|${company_id}|g" \
            -e "s|__MACHINE_ID__|${machine_id}|g" \
            -e "s|__LOCAL_MACHINE_NAME__|${machine_name}|g" \
            "$INSTALLER_DIR/.env.template" > "$MCE_ENV_FILE"
    else
        # Fallback: write .env directly
        cat > "$MCE_ENV_FILE" <<ENVEOF
# MidnightCEO Local Compute — generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMPUTE_MODE=local
MACHINE_ID=${machine_id}
COMPANY_ID=${company_id}
LOCAL_MACHINE_NAME=${machine_name}

LLM_BACKEND=api
ANTHROPIC_API_KEY=${anthropic_key}

SUPABASE_URL=${supabase_url}
SUPABASE_SERVICE_ROLE_KEY=${supabase_key}
NEXT_PUBLIC_SUPABASE_URL=${supabase_url}
NEXT_PUBLIC_SUPABASE_ANON_KEY=

REDIS_URL=redis://redis:6379/0
LOG_LEVEL=info
ENVEOF
    fi

    chmod 600 "$MCE_ENV_FILE"
    success "Configuration saved (permissions: 600)"
}

# ---------------------------------------------------------------------------
# 4. Pull Docker images
# ---------------------------------------------------------------------------

pull_docker_images() {
    header "Pulling Docker images"

    if [[ "$DEV_MODE" == true ]]; then
        info "Dev mode: building images from local source"

        if [[ ! -f "$INSTALLER_DIR/../infra/docker-compose.yml" ]]; then
            die "Cannot find project root for dev build. Ensure installer/ is inside the MidnightCEO repo."
        fi

        local project_root
        project_root="$(cd "$INSTALLER_DIR/.." && pwd)"

        docker build -t ghcr.io/flutterplaza/midnightceo-backend:latest \
            -f "$project_root/infra/Dockerfile.agents" \
            "$project_root/apps/agents" || die "Failed to build midnightceo-backend image"
        success "Built ghcr.io/flutterplaza/midnightceo-backend:latest from source"
    else
        info "Pulling redis:7-alpine..."
        docker pull redis:7-alpine || die "Failed to pull redis:7-alpine"
        success "Pulled redis:7-alpine"

        info "Pulling ghcr.io/flutterplaza/midnightceo-backend:latest..."
        docker pull ghcr.io/flutterplaza/midnightceo-backend:latest || die "Failed to pull ghcr.io/flutterplaza/midnightceo-backend:latest"
        success "Pulled ghcr.io/flutterplaza/midnightceo-backend:latest"
    fi
}

# ---------------------------------------------------------------------------
# 5. Write docker-compose.local.yml
# ---------------------------------------------------------------------------

write_docker_compose() {
    header "Installing Docker Compose configuration"

    if [[ -f "$INSTALLER_DIR/docker-compose.local.yml" ]]; then
        cp "$INSTALLER_DIR/docker-compose.local.yml" "$MCE_COMPOSE_FILE"
    else
        die "docker-compose.local.yml not found in installer directory"
    fi

    success "Docker Compose config installed at $MCE_COMPOSE_FILE"
}

# ---------------------------------------------------------------------------
# 6. Install cloudflared
# ---------------------------------------------------------------------------

install_cloudflared() {
    header "Installing cloudflared (Cloudflare Tunnel)"

    if command -v cloudflared &>/dev/null; then
        local cf_version
        cf_version="$(cloudflared --version 2>/dev/null | head -1)"
        success "cloudflared already installed: $cf_version"
        return 0
    fi

    if command -v brew &>/dev/null; then
        info "Installing via Homebrew..."
        brew install cloudflared || die "Failed to install cloudflared via Homebrew"
    else
        info "Homebrew not found. Downloading cloudflared binary directly..."
        local arch
        arch="$(uname -m)"
        local cf_url

        if [[ "$arch" == "arm64" ]]; then
            cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
        else
            cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
        fi

        local tmp_dir
        tmp_dir="$(mktemp -d)"
        trap "rm -rf '$tmp_dir'" EXIT

        curl -fsSL "$cf_url" -o "$tmp_dir/cloudflared.tgz" || die "Failed to download cloudflared"
        tar -xzf "$tmp_dir/cloudflared.tgz" -C "$tmp_dir" || die "Failed to extract cloudflared"

        sudo install -m 755 "$tmp_dir/cloudflared" /usr/local/bin/cloudflared || die "Failed to install cloudflared"

        trap - EXIT
        rm -rf "$tmp_dir"
    fi

    success "cloudflared installed: $(cloudflared --version 2>/dev/null | head -1)"
}

# ---------------------------------------------------------------------------
# 7. Install LaunchAgent
# ---------------------------------------------------------------------------

install_launchagent() {
    header "Installing LaunchAgent (auto-start on login)"

    # Unload existing agent if present
    if launchctl list "$MCE_PLIST_LABEL" &>/dev/null 2>&1; then
        info "Unloading existing LaunchAgent..."
        launchctl unload "$MCE_PLIST_PATH" 2>/dev/null || true
    fi

    # Ensure LaunchAgents directory exists
    mkdir -p "$HOME/Library/LaunchAgents"

    if [[ -f "$INSTALLER_DIR/launchagent/${MCE_PLIST_LABEL}.plist" ]]; then
        # Substitute HOME path in the template
        sed "s|__HOME__|${HOME}|g" \
            "$INSTALLER_DIR/launchagent/${MCE_PLIST_LABEL}.plist" > "$MCE_PLIST_PATH"
    else
        die "LaunchAgent plist template not found in installer directory"
    fi

    launchctl load "$MCE_PLIST_PATH" || warn "Failed to load LaunchAgent (will start on next login)"

    success "LaunchAgent installed at $MCE_PLIST_PATH"
}

# ---------------------------------------------------------------------------
# 8. Install menu bar app
# ---------------------------------------------------------------------------

install_menubar_app() {
    header "Installing menu bar status app"

    # Create Python virtual environment
    if [[ ! -d "$MCE_VENV_DIR" ]]; then
        info "Creating virtual environment..."
        python3 -m venv "$MCE_VENV_DIR" || die "Failed to create Python virtual environment. Ensure python3 is installed."
    fi

    info "Installing Python dependencies..."
    "$MCE_VENV_DIR/bin/pip" install --quiet --upgrade pip
    if [[ -f "$INSTALLER_DIR/menubar/requirements.txt" ]]; then
        "$MCE_VENV_DIR/bin/pip" install --quiet -r "$INSTALLER_DIR/menubar/requirements.txt" \
            || die "Failed to install menu bar app dependencies"
    else
        "$MCE_VENV_DIR/bin/pip" install --quiet rumps requests psutil \
            || die "Failed to install menu bar app dependencies"
    fi

    # Copy the app
    cp "$INSTALLER_DIR/menubar/app.py" "$MCE_MENUBAR_APP"
    chmod 755 "$MCE_MENUBAR_APP"

    success "Menu bar app installed at $MCE_MENUBAR_APP"
}

# ---------------------------------------------------------------------------
# 9. Install CLI
# ---------------------------------------------------------------------------

install_cli() {
    header "Installing CLI tool"

    local cli_script
    cli_script=$(cat <<'CLIEOF'
#!/usr/bin/env bash
# =============================================================================
# midnightceo — CLI for MidnightCEO Local Compute Mode
# =============================================================================

set -euo pipefail

readonly MCE_DIR="$HOME/.midnightceo"
readonly MCE_COMPOSE_FILE="$MCE_DIR/docker-compose.local.yml"
readonly MCE_ENV_FILE="$MCE_DIR/.env"
readonly MCE_LOG_DIR="$MCE_DIR/logs"
readonly MCE_VENV_DIR="$MCE_DIR/menubar-venv"
readonly MCE_MENUBAR_APP="$MCE_DIR/menubar/app.py"
readonly MCE_PLIST_LABEL="com.midnightceo.local"
readonly MCE_PLIST_PATH="$HOME/Library/LaunchAgents/${MCE_PLIST_LABEL}.plist"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()    { printf "${GREEN}[midnightceo]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[midnightceo]${NC} %s\n" "$*"; }
error()   { printf "${RED}[midnightceo]${NC} %s\n" "$*" >&2; }

cmd_start() {
    local background=false
    if [[ "${1:-}" == "--background" ]]; then
        background=true
    fi

    if [[ ! -f "$MCE_COMPOSE_FILE" ]]; then
        error "MidnightCEO is not installed. Run the installer first."
        exit 1
    fi

    info "Starting MidnightCEO services..."

    docker compose -f "$MCE_COMPOSE_FILE" up -d

    # Wait for API health
    info "Waiting for API to become healthy..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if curl -sf http://127.0.0.1:8000/health &>/dev/null; then
            info "API is healthy."
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done

    if [[ $retries -ge 30 ]]; then
        warn "API did not become healthy within 60s. Check logs with: midnightceo logs"
    fi

    # Start caffeinate in background to prevent sleep
    if ! pgrep -f "caffeinate.*midnightceo" &>/dev/null; then
        caffeinate -i -s -d &
        local caf_pid=$!
        echo "$caf_pid" > "$MCE_DIR/state/caffeinate.pid"
        info "Sleep prevention enabled (caffeinate PID: $caf_pid)"
    fi

    # Start menu bar app if not in background mode and not already running
    if [[ "$background" == false ]] && ! pgrep -f "midnightceo.*menubar" &>/dev/null; then
        if [[ -f "$MCE_MENUBAR_APP" ]] && [[ -f "$MCE_VENV_DIR/bin/python" ]]; then
            nohup "$MCE_VENV_DIR/bin/python" "$MCE_MENUBAR_APP" \
                >> "$MCE_LOG_DIR/menubar.log" 2>&1 &
            info "Menu bar app started."
        fi
    fi

    info "MidnightCEO is running. Open your console at https://console.midnightceo.ai"
}

cmd_stop() {
    info "Stopping MidnightCEO services..."

    # Stop Docker services
    if [[ -f "$MCE_COMPOSE_FILE" ]]; then
        docker compose -f "$MCE_COMPOSE_FILE" down
    fi

    # Stop caffeinate
    if [[ -f "$MCE_DIR/state/caffeinate.pid" ]]; then
        local caf_pid
        caf_pid="$(cat "$MCE_DIR/state/caffeinate.pid" 2>/dev/null || true)"
        if [[ -n "$caf_pid" ]] && kill -0 "$caf_pid" 2>/dev/null; then
            kill "$caf_pid" 2>/dev/null || true
        fi
        rm -f "$MCE_DIR/state/caffeinate.pid"
    fi

    # Stop menu bar app
    pkill -f "midnightceo.*menubar" 2>/dev/null || true
    pkill -f "rumps" 2>/dev/null || true

    info "MidnightCEO stopped."
}

cmd_status() {
    echo ""
    printf "  ${GREEN}MidnightCEO Local Compute${NC}\n"
    echo "  ─────────────────────────────"

    # Docker containers
    if [[ -f "$MCE_COMPOSE_FILE" ]]; then
        local running
        running="$(docker compose -f "$MCE_COMPOSE_FILE" ps --status running -q 2>/dev/null | wc -l | tr -d ' ')"
        local total
        total="$(docker compose -f "$MCE_COMPOSE_FILE" ps -q 2>/dev/null | wc -l | tr -d ' ')"
        printf "  Containers:  %s/%s running\n" "$running" "$total"
    else
        printf "  Containers:  not configured\n"
    fi

    # API health
    if curl -sf http://127.0.0.1:8000/health &>/dev/null; then
        printf "  API:         ${GREEN}healthy${NC}\n"
    else
        printf "  API:         ${RED}offline${NC}\n"
    fi

    # Tunnel
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "mce-tunnel"; then
        printf "  Tunnel:      ${GREEN}connected${NC}\n"
    else
        printf "  Tunnel:      ${RED}offline${NC}\n"
    fi

    # Caffeinate
    if [[ -f "$MCE_DIR/state/caffeinate.pid" ]] && kill -0 "$(cat "$MCE_DIR/state/caffeinate.pid" 2>/dev/null)" 2>/dev/null; then
        printf "  Sleep lock:  ${GREEN}active${NC}\n"
    else
        printf "  Sleep lock:  ${YELLOW}inactive${NC}\n"
    fi

    echo ""
}

cmd_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        docker compose -f "$MCE_COMPOSE_FILE" logs -f "$service"
    else
        docker compose -f "$MCE_COMPOSE_FILE" logs -f --tail=100
    fi
}

cmd_update() {
    info "Checking for updates..."

    info "Pulling latest images..."
    docker pull redis:7-alpine
    docker pull ghcr.io/flutterplaza/midnightceo-backend:latest
    docker pull cloudflare/cloudflared:latest

    info "Recreating containers..."
    docker compose -f "$MCE_COMPOSE_FILE" up -d --force-recreate

    info "Update complete."
}

cmd_help() {
    cat <<HELPEOF
Usage: midnightceo <command> [options]

Commands:
  start [--background]   Start all MidnightCEO services
  stop                   Stop all services
  status                 Show current service status
  logs [service]         Tail service logs (api, redis, tunnel)
  update                 Pull latest images and restart

Examples:
  midnightceo start              Start services with menu bar app
  midnightceo start --background Start services without menu bar app
  midnightceo logs api           Follow API logs
  midnightceo status             Check health of all services

HELPEOF
}

# Main dispatch
case "${1:-help}" in
    start)   shift; cmd_start "$@" ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    logs)    shift; cmd_logs "$@" ;;
    update)  cmd_update ;;
    help|--help|-h) cmd_help ;;
    *)
        error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
CLIEOF

    # Write the CLI script — requires sudo for /usr/local/bin
    info "Installing CLI to $MCE_CLI_PATH (may require sudo)..."

    if [[ -w "$(dirname "$MCE_CLI_PATH")" ]]; then
        echo "$cli_script" > "$MCE_CLI_PATH"
        chmod 755 "$MCE_CLI_PATH"
    else
        echo "$cli_script" | sudo tee "$MCE_CLI_PATH" > /dev/null
        sudo chmod 755 "$MCE_CLI_PATH"
    fi

    success "CLI installed: midnightceo start|stop|status|logs|update"
}

# ---------------------------------------------------------------------------
# 10. Start services
# ---------------------------------------------------------------------------

start_services() {
    header "Starting MidnightCEO services"

    # Start Docker Compose stack
    info "Starting Docker containers..."
    docker compose -f "$MCE_COMPOSE_FILE" up -d || die "Failed to start Docker containers"

    # Wait for API health
    info "Waiting for API to become healthy..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if curl -sf http://127.0.0.1:8000/health &>/dev/null; then
            success "API is healthy"
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done

    if [[ $retries -ge 30 ]]; then
        warn "API did not become healthy within 60s — it may still be starting up"
    fi

    # Start caffeinate
    caffeinate -i -s -d &
    local caf_pid=$!
    echo "$caf_pid" > "$MCE_STATE_DIR/caffeinate.pid"
    info "Sleep prevention enabled (caffeinate PID: $caf_pid)"

    # Register this machine in Supabase
    if [[ -f "$MCE_ENV_FILE" ]]; then
        # Source the env file to get credentials for registration
        local company_id supabase_url supabase_key machine_name
        company_id="$(grep '^COMPANY_ID=' "$MCE_ENV_FILE" | cut -d= -f2-)"
        supabase_url="$(grep '^SUPABASE_URL=' "$MCE_ENV_FILE" | cut -d= -f2-)"
        supabase_key="$(grep '^SUPABASE_SERVICE_ROLE_KEY=' "$MCE_ENV_FILE" | cut -d= -f2-)"
        machine_name="$(grep '^LOCAL_MACHINE_NAME=' "$MCE_ENV_FILE" | cut -d= -f2-)"

        if [[ -n "$company_id" && -n "$supabase_url" && -n "$supabase_key" ]]; then
            info "Registering local compute node in Supabase..."
            local ram_gb
            ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
            local cpu_model
            cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"

            curl -sf -X PATCH \
                "${supabase_url}/rest/v1/companies?id=eq.${company_id}" \
                -H "apikey: ${supabase_key}" \
                -H "Authorization: Bearer ${supabase_key}" \
                -H "Content-Type: application/json" \
                -H "Prefer: return=minimal" \
                -d "{
                    \"compute_mode\": \"local\",
                    \"local_machine_name\": \"${machine_name}\",
                    \"tunnel_active\": true,
                    \"local_machine_specs\": {
                        \"cpu\": \"${cpu_model}\",
                        \"ram_gb\": ${ram_gb},
                        \"os\": \"$(sw_vers -productVersion 2>/dev/null || echo 'unknown')\"
                    }
                }" && success "Registered in Supabase" \
                   || warn "Could not register in Supabase (will retry on next startup)"
        fi
    fi

    # Start menu bar app
    if [[ -f "$MCE_MENUBAR_APP" ]] && [[ -f "$MCE_VENV_DIR/bin/python" ]]; then
        nohup "$MCE_VENV_DIR/bin/python" "$MCE_MENUBAR_APP" \
            >> "$MCE_LOG_DIR/menubar.log" 2>&1 &
        success "Menu bar app started"
    fi
}

# ---------------------------------------------------------------------------
# 11. Verify installation
# ---------------------------------------------------------------------------

verify_installation() {
    header "Verifying installation"

    local all_ok=true

    # Check Docker containers
    local running_count
    running_count="$(docker compose -f "$MCE_COMPOSE_FILE" ps --status running -q 2>/dev/null | wc -l | tr -d ' ')"

    if [[ "$running_count" -ge 2 ]]; then
        success "$running_count Docker containers running"
    else
        warn "Only $running_count containers running (expected at least 2)"
        all_ok=false
    fi

    # Check CLI
    if [[ -x "$MCE_CLI_PATH" ]]; then
        success "CLI installed at $MCE_CLI_PATH"
    else
        warn "CLI not found at $MCE_CLI_PATH"
        all_ok=false
    fi

    # Check LaunchAgent
    if [[ -f "$MCE_PLIST_PATH" ]]; then
        success "LaunchAgent installed"
    else
        warn "LaunchAgent plist not found"
        all_ok=false
    fi

    # Print final summary
    echo ""
    if [[ "$all_ok" == true ]]; then
        printf "${BOLD}${GREEN}"
        echo "  ============================================"
        echo "  MidnightCEO Local Compute — INSTALLED"
        echo "  ============================================"
        printf "${NC}\n"
        echo "  Your MacBook is now running MidnightCEO."
        echo "  Leave it plugged in and running overnight."
        echo ""
        echo "  Quick commands:"
        echo "    midnightceo status     Check service health"
        echo "    midnightceo logs       View live logs"
        echo "    midnightceo stop       Stop all services"
        echo "    midnightceo update     Pull latest updates"
        echo ""
        echo "  Console: https://console.midnightceo.ai"
        echo ""
        echo "  Your MacBook will stay awake while MidnightCEO is running."
        echo "  Plug it in for best results. Agents will auto-pause below"
        echo "  20% battery to protect your machine."
        echo ""
    else
        printf "${BOLD}${YELLOW}"
        echo "  ============================================"
        echo "  MidnightCEO — INSTALLED WITH WARNINGS"
        echo "  ============================================"
        printf "${NC}\n"
        echo "  Some components may need attention."
        echo "  Run 'midnightceo status' to check."
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"

    echo ""
    printf "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     MidnightCEO Local Compute Installer  ║"
    echo "  ║          macOS Edition                    ║"
    echo "  ╚══════════════════════════════════════════╝"
    printf "${NC}\n"

    check_system_requirements
    create_midnightceo_dir
    collect_credentials
    pull_docker_images
    write_docker_compose
    install_cloudflared
    install_launchagent
    install_menubar_app
    install_cli
    start_services
    verify_installation
}

main "$@"
