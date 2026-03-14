#!/bin/bash
# =============================================================================
# MidnightCEO — Local Compute Mode Uninstall
# =============================================================================
#
# Cleanly removes MidnightCEO Local Compute Mode from this machine.
# Supabase data is preserved (it lives in the cloud).
#
# What it does:
#   1. Stops all MidnightCEO Docker containers
#   2. Removes the macOS LaunchAgent (auto-start)
#   3. Optionally removes Docker images to reclaim disk space
#   4. Asks whether to retain or delete local data (~/.midnightceo)
#   5. Cleans up system processes (cloudflared, caffeinate)
#
# Usage:
#   bash uninstall.sh
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"

CONFIG_DIR="$HOME/.midnightceo"
COMPOSE_FILE="$CONFIG_DIR/docker-compose.local.yml"
PLIST_NAME="com.midnightceo.agents"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
# Also check the legacy plist name
PLIST_FILE_LEGACY="$HOME/Library/LaunchAgents/com.midnightceo.local.plist"

MANAGED_IMAGES=(
  "midnightceo/agent-workers"
  "midnightceo/fastapi-backend"
  "midnightceo/temporal-worker"
)

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║   MidnightCEO — Uninstall                ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  This will remove MidnightCEO Local Compute Mode from this machine."
echo -e "  ${DIM}Your Supabase data and cloud configuration will NOT be affected.${NC}"
echo ""
echo "  This will:"
echo "    1. Stop all MidnightCEO Docker containers"
echo "    2. Remove the auto-start LaunchAgent"
echo "    3. Optionally remove Docker images (saves disk space)"
echo "    4. Optionally remove local data and credentials"
echo ""
echo -ne "  ${ARROW} Continue? (y/N): "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo -e "  ${DIM}Uninstall cancelled.${NC}"
  exit 0
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1: Stop Docker containers
# ---------------------------------------------------------------------------

echo -e "${BOLD}[1/6] Stopping Docker containers${NC}"
echo ""

DOCKER_AVAILABLE=false
if command -v docker &>/dev/null && docker info &>/dev/null; then
  DOCKER_AVAILABLE=true
fi

if [ "$DOCKER_AVAILABLE" = true ]; then
  # Try docker compose down with the local compose file
  if [ -f "$COMPOSE_FILE" ]; then
    if docker compose -f "$COMPOSE_FILE" down --timeout 30 2>/dev/null; then
      echo -e "  ${CHECKMARK} Docker containers stopped via docker compose"
    else
      echo -e "  ${YELLOW}⚠${NC} docker compose down failed — trying manual stop"
    fi
  fi

  # Also try the bundled compose file
  BUNDLED_COMPOSE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker-compose.local.yml"
  if [ -f "$BUNDLED_COMPOSE" ] && [ "$BUNDLED_COMPOSE" != "$COMPOSE_FILE" ]; then
    docker compose -f "$BUNDLED_COMPOSE" down --timeout 30 2>/dev/null || true
  fi

  # Force-stop any remaining containers with the midnightceo prefix
  CONTAINERS=$(docker ps -q --filter "name=midnightceo" 2>/dev/null || echo "")
  if [ -n "$CONTAINERS" ]; then
    echo -e "  ${ARROW} Force-stopping remaining MidnightCEO containers..."
    echo "$CONTAINERS" | xargs docker stop --time 10 2>/dev/null || true
    echo "$CONTAINERS" | xargs docker rm -f 2>/dev/null || true
    echo -e "  ${CHECKMARK} Remaining containers removed"
  fi

  # Remove associated Docker networks
  NETWORKS=$(docker network ls --filter "name=midnightceo" -q 2>/dev/null || echo "")
  if [ -n "$NETWORKS" ]; then
    echo "$NETWORKS" | xargs docker network rm 2>/dev/null || true
    echo -e "  ${CHECKMARK} Docker networks removed"
  fi

  # Remove associated Docker volumes
  VOLUMES=$(docker volume ls --filter "name=midnightceo" -q 2>/dev/null || echo "")
  if [ -n "$VOLUMES" ]; then
    echo -ne "  ${ARROW} Remove Docker volumes (redis-data, agent-state)? This deletes cached data. (y/N): "
    read -r REMOVE_VOLUMES
    if [ "$REMOVE_VOLUMES" = "y" ] || [ "$REMOVE_VOLUMES" = "Y" ]; then
      echo "$VOLUMES" | xargs docker volume rm 2>/dev/null || true
      echo -e "  ${CHECKMARK} Docker volumes removed"
    else
      echo -e "  ${DIM}Keeping Docker volumes${NC}"
    fi
  fi

  echo -e "  ${CHECKMARK} All MidnightCEO containers stopped"
else
  echo -e "  ${DIM}Docker is not running — skipping container cleanup${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Remove LaunchAgent
# ---------------------------------------------------------------------------

echo -e "${BOLD}[2/6] Removing LaunchAgent${NC}"
echo ""

REMOVED_PLIST=false

# Remove current plist
if [ -f "$PLIST_FILE" ]; then
  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  rm -f "$PLIST_FILE"
  echo -e "  ${CHECKMARK} LaunchAgent removed: ${PLIST_FILE}"
  REMOVED_PLIST=true
fi

# Remove legacy plist
if [ -f "$PLIST_FILE_LEGACY" ]; then
  launchctl unload "$PLIST_FILE_LEGACY" 2>/dev/null || true
  rm -f "$PLIST_FILE_LEGACY"
  echo -e "  ${CHECKMARK} Legacy LaunchAgent removed: ${PLIST_FILE_LEGACY}"
  REMOVED_PLIST=true
fi

if [ "$REMOVED_PLIST" = false ]; then
  echo -e "  ${DIM}No LaunchAgent found — skipping${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 3: Clean up Docker images
# ---------------------------------------------------------------------------

echo -e "${BOLD}[3/6] Cleaning up Docker images${NC}"
echo ""

if [ "$DOCKER_AVAILABLE" = true ]; then
  echo -ne "  ${ARROW} Remove MidnightCEO Docker images? This saves disk space. (y/N): "
  read -r REMOVE_IMAGES

  if [ "$REMOVE_IMAGES" = "y" ] || [ "$REMOVE_IMAGES" = "Y" ]; then
    for IMAGE_NAME in "${MANAGED_IMAGES[@]}"; do
      IMAGE_IDS=$(docker images "$IMAGE_NAME" -q 2>/dev/null || echo "")
      if [ -n "$IMAGE_IDS" ]; then
        echo "$IMAGE_IDS" | sort -u | xargs docker rmi -f 2>/dev/null || true
        echo -e "  ${CHECKMARK} Removed: ${IMAGE_NAME}"
      else
        echo -e "  ${DIM}Not found: ${IMAGE_NAME}${NC}"
      fi
    done

    # Cloudflared image
    CF_IMAGE_IDS=$(docker images "cloudflare/cloudflared" -q 2>/dev/null || echo "")
    if [ -n "$CF_IMAGE_IDS" ]; then
      echo -ne "  ${ARROW} Remove cloudflare/cloudflared image? (y/N): "
      read -r REMOVE_CF
      if [ "$REMOVE_CF" = "y" ] || [ "$REMOVE_CF" = "Y" ]; then
        echo "$CF_IMAGE_IDS" | sort -u | xargs docker rmi -f 2>/dev/null || true
        echo -e "  ${CHECKMARK} Removed: cloudflare/cloudflared"
      fi
    fi

    # Redis image — check if any non-midnightceo containers use it
    REDIS_CONTAINERS=$(docker ps -a --filter "ancestor=redis:7-alpine" --format "{{.Names}}" 2>/dev/null | grep -v midnightceo || echo "")
    if [ -z "$REDIS_CONTAINERS" ]; then
      echo -ne "  ${ARROW} Remove Redis image (redis:7-alpine)? (y/N): "
      read -r REMOVE_REDIS
      if [ "$REMOVE_REDIS" = "y" ] || [ "$REMOVE_REDIS" = "Y" ]; then
        docker rmi -f redis:7-alpine 2>/dev/null || true
        echo -e "  ${CHECKMARK} Removed: redis:7-alpine"
      fi
    else
      echo -e "  ${DIM}Keeping redis:7-alpine — used by other containers${NC}"
    fi

    # Prune dangling images
    docker image prune -f 2>/dev/null || true
    echo -e "  ${CHECKMARK} Dangling images pruned"
  else
    echo -e "  ${DIM}Keeping Docker images${NC}"
  fi
else
  echo -e "  ${DIM}Docker is not available — skipping image cleanup${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Data retention
# ---------------------------------------------------------------------------

echo -e "${BOLD}[4/6] Data retention${NC}"
echo ""

if [ -d "$CONFIG_DIR" ]; then
  echo "  Your local data is stored at: ${CONFIG_DIR}"
  echo ""
  echo "  This directory contains:"

  if [ -f "$CONFIG_DIR/.env" ]; then
    echo "    - .env (API keys and configuration)"
  fi
  if [ -f "$CONFIG_DIR/docker-compose.local.yml" ]; then
    echo "    - docker-compose.local.yml"
  fi
  if [ -d "$CONFIG_DIR/data" ]; then
    DATA_SIZE=$(du -sh "$CONFIG_DIR/data" 2>/dev/null | awk '{print $1}')
    echo "    - data/ (agent state, Redis data) — ${DATA_SIZE:-unknown}"
  fi
  if [ -f "$CONFIG_DIR/midnightceo.log" ]; then
    echo "    - midnightceo.log"
  fi
  if [ -f "$CONFIG_DIR/setup.log" ]; then
    echo "    - setup.log"
  fi
  echo ""

  echo -e "  ${BOLD}What would you like to do with your local data?${NC}"
  echo ""
  echo "    [k] Keep everything (recommended if you may reinstall)"
  echo "    [c] Keep data, remove credentials (.env)"
  echo "    [d] Delete everything"
  echo ""
  echo -ne "  ${ARROW} Choice [k/c/d]: "
  read -r DATA_CHOICE

  case "$DATA_CHOICE" in
    d|D)
      # Offer to back up .env first
      if [ -f "$CONFIG_DIR/.env" ]; then
        BACKUP_PATH="$HOME/Desktop/midnightceo-env-backup-$(date +%Y%m%d).txt"
        echo -ne "  ${ARROW} Back up .env to Desktop before deleting? (Y/n): "
        read -r BACKUP
        if [ "$BACKUP" != "n" ] && [ "$BACKUP" != "N" ]; then
          cp "$CONFIG_DIR/.env" "$BACKUP_PATH"
          chmod 600 "$BACKUP_PATH"
          echo -e "  ${CHECKMARK} .env backed up to $BACKUP_PATH"
        fi
      fi
      rm -rf "$CONFIG_DIR"
      echo -e "  ${CHECKMARK} All local data deleted"
      ;;
    c|C)
      rm -f "$CONFIG_DIR/.env"
      echo -e "  ${CHECKMARK} Credentials removed. Data directory kept at ${CONFIG_DIR}"
      ;;
    *)
      echo -e "  ${DIM}Keeping all local data at ${CONFIG_DIR}${NC}"
      ;;
  esac
else
  echo -e "  ${DIM}No config directory found — nothing to clean up${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 5: Clean up system processes
# ---------------------------------------------------------------------------

echo -e "${BOLD}[5/6] Cleaning up system processes${NC}"
echo ""

# Kill any running cloudflared processes started by MidnightCEO
if pgrep -f "cloudflared.*midnightceo" > /dev/null 2>&1; then
  pkill -f "cloudflared.*midnightceo" 2>/dev/null || true
  echo -e "  ${CHECKMARK} Stopped cloudflared tunnel processes"
else
  echo -e "  ${DIM}No active tunnel processes found${NC}"
fi

# Our caffeinate is process-scoped, so it should already be gone,
# but clean up just in case
if pgrep -f "caffeinate.*midnightceo" > /dev/null 2>&1; then
  pkill -f "caffeinate.*midnightceo" 2>/dev/null || true
  echo -e "  ${CHECKMARK} Stopped caffeinate processes"
else
  echo -e "  ${DIM}No caffeinate processes to clean up${NC}"
fi

# We do NOT uninstall cloudflared itself — it may be used by other tools
echo -e "  ${DIM}Note: cloudflared binary was not removed (may be used by other tools)${NC}"

echo ""

# ---------------------------------------------------------------------------
# Step 6: Remove Electron app artifacts
# ---------------------------------------------------------------------------

echo -e "${BOLD}[6/6] Cleaning up application artifacts${NC}"
echo ""

# electron-store settings
APP_SUPPORT_DIR="$HOME/Library/Application Support/midnightceo-local"
if [ -d "$APP_SUPPORT_DIR" ]; then
  rm -rf "$APP_SUPPORT_DIR"
  echo -e "  ${CHECKMARK} Removed app settings from Application Support"
else
  echo -e "  ${DIM}No Application Support directory found${NC}"
fi

# Preferences plist
PREFS_PLIST="$HOME/Library/Preferences/com.midnightceo.local.plist"
if [ -f "$PREFS_PLIST" ]; then
  rm -f "$PREFS_PLIST"
  echo -e "  ${CHECKMARK} Removed preferences plist"
fi

# Caches
CACHES_DIR="$HOME/Library/Caches/com.midnightceo.local"
if [ -d "$CACHES_DIR" ]; then
  rm -rf "$CACHES_DIR"
  echo -e "  ${CHECKMARK} Removed app caches"
fi

# Electron Crashpad data
CRASHPAD_DIR="$HOME/Library/Application Support/com.midnightceo.local/Crashpad"
if [ -d "$CRASHPAD_DIR" ]; then
  rm -rf "$CRASHPAD_DIR"
  echo -e "  ${CHECKMARK} Removed crash reporter data"
fi

echo ""

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║     Uninstall complete.                  ║"
echo "  ║                                          ║"
echo "  ║     Your cloud data is untouched.        ║"
echo "  ║     You can re-install at any time.      ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${DIM}To switch to Cloud Mode in the console, visit:${NC}"
echo -e "  ${DIM}https://console.midnightceo.ai/settings${NC}"
echo ""
