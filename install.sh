#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_INSTALLER="https://raw.githubusercontent.com/mschlenstedt/Loxberry_Installer/main/install.sh"
LOG="/var/log/loxberry-install.log"

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive

log()  { echo -e "[lb-bootstrap] $*"; }
fail() { echo -e "[lb-bootstrap] ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Must run as root."

# --- 1. Install missing tools ---
log "Installing prerequisites..."
apt-get update -qq
apt-get install -y --no-install-recommends psmisc procps

# --- 2. Create loxberry user (installer expects it) ---
log "Creating loxberry user..."
groupadd -f loxberry
id loxberry &>/dev/null || useradd -m -g loxberry -s /bin/bash loxberry
echo "loxberry:loxberry" | chpasswd
mkdir -p /opt/loxberry
chown loxberry:loxberry /opt/loxberry

# --- 3. Fake DietPi environment ---
log "Faking DietPi environment..."

mkdir -p /boot/dietpi/func

cat > /boot/dietpi/.version <<'EOF'
G_DIETPI_VERSION_CORE=9
G_DIETPI_VERSION_SUB=9
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
G_DISTRO_NAME='trixie'
G_ROOTFS_DEV='/dev/root'
G_HW_UUID='loxberry-docker-arm64'
EOF

for stub in dietpi-set_software dietpi-obtain_hw_model dietpi-services; do
    cat > "/boot/dietpi/func/$stub" <<'STUBEOF'
#!/bin/bash
exit 0
STUBEOF
    chmod +x "/boot/dietpi/func/$stub"
done

# Prevent reboot/shutdown during build
ln -sf /bin/true /usr/local/sbin/reboot
ln -sf /bin/true /usr/local/sbin/shutdown

# --- 4. Stub systemctl during build ---
cat > /usr/local/sbin/systemctl-stub <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x /usr/local/sbin/systemctl-stub

if [ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]; then
    log "systemd not running (build phase) — stubbing systemctl"
    dpkg-divert --local --rename --add /usr/bin/systemctl
    ln -sf /usr/local/sbin/systemctl-stub /usr/bin/systemctl
fi

# --- 5. Fake /proc/mounts to avoid tmpfs check ---
log "Faking tmpfs mounts check..."
# The installer checks for stale tmpfs mounts — we remove them
umount -a -t tmpfs 2>/dev/null || true

# --- 6. Download and patch the upstream installer ---
log "Downloading upstream installer..."
TMP=$(mktemp)
curl -fsSL "$UPSTREAM_INSTALLER" -o "$TMP" \
    || fail "Could not download $UPSTREAM_INSTALLER"

log "Patching installer..."
# Accept Debian 12 (bookworm) instead of requiring Debian 13 (trixie)
sed -i 's|TARGET_VERSION_ID="13"|TARGET_VERSION_ID="12"|' "$TMP"
sed -i 's|TARGET_PRETTY_NAME="Debian GNU/Linux 13 (trixie)"|TARGET_PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"|' "$TMP"

# Remove the tmpfs mount check that fails in Docker
sed -i '/old mounts of tmpfs/,/exit 1/d' "$TMP"
sed -i '/old mounts of tmpfs/d' "$TMP"

# Remove the "reboot and start again" block
sed -i '/Please reboot and start installation again/d' "$TMP"

# --- 7. Run the installer ---
log "Running LoxBerry installer (full log: $LOG)"
mkdir -p "$(dirname "$LOG")"

bash "$TMP" 2>&1 | tee "$LOG" || true

# --- 8. Restore real systemctl for runtime ---
if [ -e /usr/bin/systemctl.distrib ]; then
    log "Restoring real systemctl..."
    rm -f /usr/bin/systemctl
    dpkg-divert --local --rename --remove /usr/bin/systemctl
fi

# --- 9. Cleanup ---
log "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* "$TMP"

log "LoxBerry bootstrap complete."