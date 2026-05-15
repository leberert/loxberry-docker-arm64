#!/usr/bin/env bash
# install.sh — bootstrap LoxBerry inside a Docker container on ARM64
#
# Why this exists:
#   The upstream installer (mschlenstedt/Loxberry_Installer) hard-checks for
#   DietPi and refuses to run anywhere else. We fake just enough of DietPi to
#   pass that check, then hand off to the official installer.

set -euo pipefail

UPSTREAM_INSTALLER="https://raw.githubusercontent.com/mschlenstedt/Loxberry_Installer/main/install.sh"
LOG="/var/log/loxberry-install.log"

log()  { echo -e "\033[1;36m[lb-bootstrap]\033[0m $*"; }
fail() { echo -e "\033[1;31m[lb-bootstrap] ERROR:\033[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Must run as root."

# ---------------------------------------------------------------------------
# 1. Fake the DietPi environment
# ---------------------------------------------------------------------------
log "Faking DietPi environment..."

mkdir -p /boot/dietpi/func

cat > /boot/dietpi/.version <<'EOF'
G_DIETPI_VERSION_CORE=9
G_DIETPI_VERSION_SUB=5
G_DIETPI_VERSION_RC=1
G_GITBRANCH='master'
G_GITOWNER='MichaIng'
EOF

cat > /boot/dietpi/.hw_model <<'EOF'
G_HW_MODEL=4
G_HW_MODEL_NAME='RPi 4 Model B (aarch64)'
G_HW_ARCH=3
G_HW_ARCH_NAME='aarch64'
G_HW_CPUID=0
G_HW_CPU_CORES=4
G_DISTRO=7
G_DISTRO_NAME='bookworm'
G_ROOTFS_DEV='/dev/root'
G_HW_UUID='loxberry-docker-arm64'
EOF

# Stub out the DietPi helpers the installer pokes at
for stub in dietpi-set_software dietpi-obtain_hw_model dietpi-services; do
    cat > "/boot/dietpi/func/$stub" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "/boot/dietpi/func/$stub"
done

# Prevent the installer from rebooting mid-build (we're in Docker!)
ln -sf /bin/true /usr/local/sbin/reboot
ln -sf /bin/true /usr/local/sbin/shutdown

# Mark filesystem as "already resized" so the installer skips that step
touch /boot/rootfsresized.skip   # informational only
> /boot/dietpi/.install_stage    # signals "ready to install"
echo 2 > /boot/dietpi/.install_stage

# ---------------------------------------------------------------------------
# 2. Run the upstream LoxBerry installer
# ---------------------------------------------------------------------------
log "Downloading upstream installer..."
TMP=$(mktemp)
curl -fsSL "$UPSTREAM_INSTALLER" -o "$TMP" \
    || fail "Could not download $UPSTREAM_INSTALLER"

log "Running LoxBerry installer (full log: $LOG)"
mkdir -p "$(dirname "$LOG")"

# Patch out the DietPi distribution check at runtime (belt + braces)
sed -i 's|exit 1 # DietPi-check|: # patched|g' "$TMP" || true

bash "$TMP" 2>&1 | tee "$LOG"

# ---------------------------------------------------------------------------
# 3. Post-install cleanup
# ---------------------------------------------------------------------------
log "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* "$TMP"

log "LoxBerry bootstrap complete."
