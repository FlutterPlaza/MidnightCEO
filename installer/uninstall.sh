#!/usr/bin/env bash
# =============================================================================
# MidnightCEO — Uninstaller for Local Compute Mode
#
# Cleanly removes all MidnightCEO components from the system.
# =============================================================================

set -euo pipefail

readonly MCE_DIR="$HOME/.midnightceo"
readonly MCE_COMPOSE_FILE="$MCE_DIR/docker-compose.local.yml"
readonly MCE_CLI_PATH="/usr/local/bin/midnightceo"
readonly MCE_PLIST_LABEL="com.midnightceo.local"
readonly MCE_PLIST_PATH="$HOME/Library/LaunchAgents/${MCE_PLIST_LABEL}.plist"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

info()    { printf "${GREEN}[uninstall]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[uninstall]${NC} %s\n" "$*"; }

echo ""
printf "${BOLD}${RED}  MidnightCEO — Uninstaller${NC}\n"
echo ""
printf "  This will remove MidnightCEO Local Compute from your system.\n"
printf "  Confirm? [y/N] "
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi

# 1. Unload LaunchAgent
if launchctl list "$MCE_PLIST_LABEL" &>/dev/null 2>&1; then
    info "Unloading LaunchAgent..."
    launchctl unload "$MCE_PLIST_PATH" 2>/dev/null || true
fi

# 2. Stop and remove Docker containers + volumes
if [[ -f "$MCE_COMPOSE_FILE" ]]; then
    info "Stopping Docker containers and removing volumes..."
    docker compose -f "$MCE_COMPOSE_FILE" down -v 2>/dev/null || true
fi

# 3. Stop caffeinate
if [[ -f "$MCE_DIR/state/caffeinate.pid" ]]; then
    caf_pid="$(cat "$MCE_DIR/state/caffeinate.pid" 2>/dev/null || true)"
    if [[ -n "$caf_pid" ]] && kill -0 "$caf_pid" 2>/dev/null; then
        kill "$caf_pid" 2>/dev/null || true
    fi
fi

# 4. Stop menu bar app
pkill -f "midnightceo.*menubar" 2>/dev/null || true
pkill -f "rumps" 2>/dev/null || true

# 5. Remove MidnightCEO directory
if [[ -d "$MCE_DIR" ]]; then
    info "Removing $MCE_DIR..."
    rm -rf "$MCE_DIR"
fi

# 6. Remove LaunchAgent plist
if [[ -f "$MCE_PLIST_PATH" ]]; then
    info "Removing LaunchAgent plist..."
    rm -f "$MCE_PLIST_PATH"
fi

# 7. Remove CLI
if [[ -f "$MCE_CLI_PATH" ]]; then
    info "Removing CLI at $MCE_CLI_PATH..."
    if [[ -w "$(dirname "$MCE_CLI_PATH")" ]]; then
        rm -f "$MCE_CLI_PATH"
    else
        sudo rm -f "$MCE_CLI_PATH"
    fi
fi

echo ""
info "MidnightCEO has been completely removed from your system."
info "Your Supabase data and cloud resources are unaffected."
echo ""
