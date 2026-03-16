#!/usr/bin/env bash
# =============================================================================
# MidnightCEO — macOS .pkg Builder
#
# Builds a distributable MidnightCEO-Installer.pkg using pkgbuild.
# The package includes a postinstall script that runs install.sh.
#
# Usage:
#   cd installer/pkg && ./build-pkg.sh
#
# Output:
#   ./MidnightCEO-Installer.pkg
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly INSTALLER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_DIR="$SCRIPT_DIR/build"
readonly PAYLOAD_DIR="$BUILD_DIR/payload"
readonly SCRIPTS_DIR="$BUILD_DIR/scripts"
readonly PKG_OUTPUT="$SCRIPT_DIR/MidnightCEO-Installer.pkg"
readonly PKG_IDENTIFIER="com.midnightceo.installer"
readonly PKG_VERSION="1.0.0"

info() { printf "\033[0;34m[build]\033[0m %s\n" "$*"; }
success() { printf "\033[0;32m[build]\033[0m %s\n" "$*"; }
die() { printf "\033[0;31m[build]\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Clean previous build
# ---------------------------------------------------------------------------

info "Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR"
rm -f "$PKG_OUTPUT"

# ---------------------------------------------------------------------------
# Prepare payload
# ---------------------------------------------------------------------------

info "Preparing payload..."
mkdir -p "$PAYLOAD_DIR/usr/local/share/midnightceo-installer"
mkdir -p "$SCRIPTS_DIR"

# Copy all installer files into the payload
cp "$INSTALLER_DIR/install.sh" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/"
cp "$INSTALLER_DIR/uninstall.sh" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/"
cp "$INSTALLER_DIR/docker-compose.local.yml" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/"
cp "$INSTALLER_DIR/.env.template" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/"

# Copy launchagent template
mkdir -p "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/launchagent"
cp "$INSTALLER_DIR/launchagent/com.midnightceo.local.plist" \
   "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/launchagent/"

# Copy menubar app
mkdir -p "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/menubar"
cp "$INSTALLER_DIR/menubar/app.py" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/menubar/"
cp "$INSTALLER_DIR/menubar/requirements.txt" "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/menubar/"

# Ensure install script is executable inside payload
chmod 755 "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/install.sh"
chmod 755 "$PAYLOAD_DIR/usr/local/share/midnightceo-installer/uninstall.sh"

# ---------------------------------------------------------------------------
# Create postinstall script
# ---------------------------------------------------------------------------

info "Creating postinstall script..."

cat > "$SCRIPTS_DIR/postinstall" <<'POSTINSTALL'
#!/usr/bin/env bash
# =============================================================================
# MidnightCEO — pkg postinstall script
#
# Runs the main installer after the .pkg payload has been extracted.
# This script runs as the installing user via the macOS Installer.
# =============================================================================

set -euo pipefail

INSTALL_SRC="/usr/local/share/midnightceo-installer"
LOG_FILE="/tmp/midnightceo-install.log"

echo "MidnightCEO postinstall starting at $(date)" >> "$LOG_FILE"

# The pkg installer may run as root. We need to find the actual user.
if [[ -n "${USER:-}" && "$USER" != "root" ]]; then
    REAL_USER="$USER"
elif [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "$USER")"
fi

REAL_HOME="$(dscl . -read /Users/"$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$REAL_HOME" ]]; then
    REAL_HOME="/Users/$REAL_USER"
fi

echo "Installing for user: $REAL_USER (home: $REAL_HOME)" >> "$LOG_FILE"

# Run the install script as the real user
if [[ "$(id -u)" -eq 0 ]]; then
    su "$REAL_USER" -c "bash '$INSTALL_SRC/install.sh'" >> "$LOG_FILE" 2>&1
else
    bash "$INSTALL_SRC/install.sh" >> "$LOG_FILE" 2>&1
fi

echo "MidnightCEO postinstall completed at $(date)" >> "$LOG_FILE"

exit 0
POSTINSTALL

chmod 755 "$SCRIPTS_DIR/postinstall"

# ---------------------------------------------------------------------------
# Build the .pkg
# ---------------------------------------------------------------------------

info "Building .pkg with pkgbuild..."

pkgbuild \
    --root "$PAYLOAD_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    --install-location "/" \
    "$PKG_OUTPUT" || die "pkgbuild failed"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

success "Package built successfully!"
echo ""
echo "  Output:     $PKG_OUTPUT"
echo "  Identifier: $PKG_IDENTIFIER"
echo "  Version:    $PKG_VERSION"
echo "  Size:       $(du -h "$PKG_OUTPUT" | cut -f1)"
echo ""
echo "  To install: open $PKG_OUTPUT"
echo "  Or:         sudo installer -pkg $PKG_OUTPUT -target /"
echo ""

# ---------------------------------------------------------------------------
# Cleanup build directory (keep the .pkg)
# ---------------------------------------------------------------------------

rm -rf "$BUILD_DIR"
success "Build artifacts cleaned up."
