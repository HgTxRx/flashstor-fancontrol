#!/bin/bash

: <<'EOF'
Asustor Flashstor kernel module check/compile script for Proxmox
Checks to see if the necessary it87 kmod exists, installs it if not
Uses DKMS for automatic recompilation on kernel updates
By Bernard Mc Clement, Sept 2023
Updated for Proxmox with systemd (Nov 2024)
EOF

set -e  # Exit on error

LOG_FILE="/var/log/asustor-fancontrol.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

log "Starting Asustor IT87 kernel module check"

# Check if the kmod exists and is loaded
if lsmod | grep -q asustor_it87; then
    log "SUCCESS: asustor-it87 kmod is already installed and loaded"
    exit 0
fi

log "WARNING: asustor-it87 kmod not found. Attempting to compile and install..."

# Set working directory
WORK_DIR="/tmp/asustor-platform-driver-build"
REPO_URL="https://github.com/mafredri/asustor-platform-driver"
REPO_BRANCH="it87"

# Create/clean working directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log "Cloning repository from $REPO_URL (branch: $REPO_BRANCH)..."
if ! git clone --branch "$REPO_BRANCH" "$REPO_URL" . 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Failed to clone repository"
    exit 1
fi

log "Checking for DKMS..."
if ! command -v dkms &> /dev/null; then
    log "WARNING: DKMS not found. Installing..."
    if ! apt-get update && apt-get install -y dkms 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Failed to install DKMS"
        exit 1
    fi
fi

log "Compiling kernel module..."
if ! make 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Failed to compile kernel module"
    exit 1
fi

log "Installing kernel module with DKMS..."
if ! make dkms 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Failed to install with DKMS"
    exit 1
fi

# Verify module is loaded
if ! modprobe asustor_it87 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Failed to load module"
    exit 1
fi

log "SUCCESS: asustor-it87 kmod compiled, installed, and loaded successfully"
exit 0
