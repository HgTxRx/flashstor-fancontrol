# Installing Asustor Fan Control on Proxmox

This guide covers installing the Asustor fan control system on **Proxmox** (bare metal) using systemd for automation and DKMS for kernel module persistence.

## Overview

Unlike TrueNAS (which uses its own init system), Proxmox uses **systemd** for service management. This approach:

- Uses **systemd services** to replace TrueNAS's Post-Init scripts
- Uses **DKMS** (Dynamic Kernel Module Support) to persist the kernel module across kernel updates
- Provides automatic restart on crash
- Gives standard systemd logging and monitoring

```
System Boot
  ↓
systemd triggers asustor-fancontrol.service
  ├─ Checks if kernel module exists
  ├─ If missing: compiles and registers with DKMS
  └─ Runs check_asustor_it87.kmod.sh
  ↓
systemd triggers asustor-fancontrol-monitor.service
  └─ Launches temp_monitor.sh in background
```

---

## Prerequisites

- Proxmox host system (bare metal or VM)
- Asustor Flashstor 6 or 12 Pro device (or compatible hardware with IT8625E chip)
- Root/sudo access
- Internet connectivity (for initial git clone)

---

## Installation Steps

### 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y dkms build-essential git
```

### 2. Copy Scripts to /home/admin/

```bash
# Create directory if it doesn't exist
sudo mkdir -p /home/admin

# Copy the fan control scripts from this repository
sudo cp temp_monitor.sh /home/admin/
sudo cp proxmox/check_asustor_it87.kmod.sh /home/admin/

# Make scripts executable
sudo chmod +x /home/admin/temp_monitor.sh
sudo chmod +x /home/admin/check_asustor_it87.kmod.sh
```

### 3. Create systemd Service Files

#### Option A: Using the provided files (easiest)

```bash
sudo cp proxmox/asustor-fancontrol.service /etc/systemd/system/
sudo cp proxmox/asustor-fancontrol-monitor.service /etc/systemd/system/
```

#### Option B: Create manually

Create `/etc/systemd/system/asustor-fancontrol.service`:

```bash
sudo tee /etc/systemd/system/asustor-fancontrol.service > /dev/null <<'EOF'
[Unit]
Description=Asustor IT87 Kernel Module Setup
Before=asustor-fancontrol-monitor.service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/admin/check_asustor_it87.kmod.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
EOF
```

Create `/etc/systemd/system/asustor-fancontrol-monitor.service`:

```bash
sudo tee /etc/systemd/system/asustor-fancontrol-monitor.service > /dev/null <<'EOF'
[Unit]
Description=Asustor Temperature Monitoring & Fan Control
After=asustor-fancontrol.service
Requires=asustor-fancontrol.service

[Service]
Type=simple
ExecStart=/home/admin/temp_monitor.sh
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
User=root
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
```

### 4. Enable and Start Services

```bash
# Reload systemd to recognize the new services
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable asustor-fancontrol.service
sudo systemctl enable asustor-fancontrol-monitor.service

# Start services immediately
sudo systemctl start asustor-fancontrol.service
sudo systemctl start asustor-fancontrol-monitor.service
```

### 5. Verify Installation

```bash
# Check service status
sudo systemctl status asustor-fancontrol.service
sudo systemctl status asustor-fancontrol-monitor.service

# Verify module is loaded
lsmod | grep asustor_it87

# Check DKMS status
sudo dkms status

# View logs
sudo journalctl -u asustor-fancontrol-monitor.service -n 50
```

---

## Configuration

### Tuning Fan Behavior

Edit `/home/admin/temp_monitor.sh` and modify these variables at the top:

```bash
# How often to check temps (seconds)
frequency=10

# NVMe temperature threshold (Celsius)
hdd_threshold=35

# System temperature threshold (Celsius)
sys_threshold=50

# Minimum fan speed (PWM 0-255)
min_pwm=60

# Temperature deltas to prevent fan hunting (Celsius)
hdd_delta_threshold=2
sys_delta_threshold=4

# Email alerts (set to 0 to disable)
mailalerts=0
```

After editing, restart the service:

```bash
sudo systemctl restart asustor-fancontrol-monitor.service
```

---

## Monitoring & Troubleshooting

### View Real-Time Logs

```bash
sudo journalctl -u asustor-fancontrol-monitor.service -f
```

### Check Module Status

```bash
# See if module is loaded
lsmod | grep asustor_it87

# See detailed module info
modinfo asustor_it87

# Check DKMS tracking
sudo dkms status
```

### View Full Installation Log

```bash
sudo cat /var/log/asustor-fancontrol.log
```

### Restart Services

```bash
# Restart just the fan monitoring
sudo systemctl restart asustor-fancontrol-monitor.service

# Restart everything (module check + fan monitoring)
sudo systemctl restart asustor-fancontrol.service
sudo systemctl restart asustor-fancontrol-monitor.service
```

### Check Fan is Actually Responding

```bash
# Read current fan RPM
cat /sys/class/hwmon/hwmon*/fan1_input

# Monitor in real-time
watch -n 1 'cat /sys/class/hwmon/hwmon*/fan1_input'

# Or use sensors command
sensors
```

### Debugging

Enable debug output in `temp_monitor.sh`:

```bash
# At the top of temp_monitor.sh, change:
debug=0  # to debug=2 or debug=3
```

Restart and watch logs:

```bash
sudo systemctl restart asustor-fancontrol-monitor.service
sudo journalctl -u asustor-fancontrol-monitor.service -f
```

---

## What Happens on Kernel Updates

When you run `apt upgrade` and a new kernel is installed:

1. Proxmox installs new kernel
2. DKMS automatically detects the kernel change
3. DKMS recompiles `asustor_it87` module for new kernel
4. After reboot, systemd loads the module and starts fan control
5. **No manual intervention needed**

To verify DKMS handled it:

```bash
sudo dkms status
# Output should show: asustor-it87, 1.0, [version], x86_64: installed
```

---

## Systemd Service Details

### asustor-fancontrol.service (Module Setup)

**What it does:**
- Runs once at boot
- Checks if kernel module is loaded
- If missing: compiles and installs with DKMS
- Prevents fan-monitor service from starting until module is ready

**Key options:**
- `Type=oneshot` - Runs once and exits
- `RemainAfterExit=yes` - Stays marked as "active" after exit
- `Before=asustor-fancontrol-monitor.service` - Ensures it runs first

### asustor-fancontrol-monitor.service (Fan Control)

**What it does:**
- Runs `temp_monitor.sh` in foreground
- Monitors systemd, restarts if script crashes
- Waits for module service to complete first

**Key options:**
- `Type=simple` - Runs in foreground, systemd monitors it
- `Restart=on-failure` - Restarts if exit code is non-zero
- `RestartSec=10` - Waits 10 seconds before restarting
- `StartLimitBurst=3` - Max 3 restarts per 60 seconds (prevents restart loops)

---

## Comparison: TrueNAS vs Proxmox

| Feature | TrueNAS | Proxmox |
|---------|---------|---------|
| **Boot automation** | TrueNAS UI → Post-Init scripts | systemd services |
| **Module persistence** | TrueNAS DKMS | Standard DKMS package |
| **Auto-restart on crash** | No | Yes (Restart=on-failure) |
| **Logging** | TrueNAS logs | systemd journal |
| **Kernel updates** | TrueNAS automatic | DKMS automatic |
| **Service management** | TrueNAS-specific | Standard systemd (Linux-wide) |
| **Portability** | TrueNAS only | Any systemd-based Linux |

---

## Uninstallation

To remove fan control:

```bash
# Stop services
sudo systemctl stop asustor-fancontrol-monitor.service
sudo systemctl stop asustor-fancontrol.service

# Disable from boot
sudo systemctl disable asustor-fancontrol-monitor.service
sudo systemctl disable asustor-fancontrol.service

# Remove service files
sudo rm /etc/systemd/system/asustor-fancontrol*.service
sudo systemctl daemon-reload

# Uninstall module from DKMS
sudo dkms remove asustor-it87/1.0 --all

# Remove scripts
sudo rm /home/admin/check_asustor_it87.kmod.sh
sudo rm /home/admin/temp_monitor.sh

# Remove logs
sudo rm /var/log/asustor-fancontrol.log
```

---

## Troubleshooting Common Issues

### Module fails to compile on kernel update

```bash
# Check DKMS build log
sudo dkms status
sudo dkms build asustor-it87/1.0

# Manually rebuild
cd /tmp/asustor-platform-driver-build
sudo make clean
sudo make
sudo make dkms
```

### Fan control script crashes repeatedly

```bash
# Check logs for errors
sudo journalctl -u asustor-fancontrol-monitor.service -n 100

# Verify hwmon paths are correct
ls -la /sys/class/hwmon/

# Run script manually for debugging
sudo /home/admin/temp_monitor.sh
```

### hwmon paths not found

The script dynamically finds hwmon devices. If missing:

```bash
# Check if module is loaded
lsmod | grep asustor_it87

# Force reload
sudo modprobe -r asustor_it87
sudo modprobe asustor_it87

# Verify sensors are visible
sensors
```

### Service won't start after reboot

Check if module service succeeded:

```bash
sudo systemctl status asustor-fancontrol.service
sudo journalctl -u asustor-fancontrol.service -n 50
```

If module service failed, check the log:

```bash
sudo cat /var/log/asustor-fancontrol.log
```

---

## Support & Questions

For issues specific to:
- **Proxmox systemd integration** - See this file
- **Fan control logic** - See the main [README.md](README.md)
- **Kernel module** - See [mafredri's asustor-platform-driver](https://github.com/mafredri/asustor-platform-driver)
