#!/bin/bash

# Fan calibration analyzer
# Analyzes PWM-to-RPM data and suggests tuning parameters

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <calibration-csv-file>"
    echo ""
    echo "Example: $0 /tmp/fan-calibration-20241107-231000.csv"
    echo ""
    echo "First run: calibrate-fan.sh to generate calibration data"
    exit 1
fi

CSV_FILE="$1"

# Verify file exists
if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}ERROR: File not found: $CSV_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}=== Fan Calibration Analysis ===${NC}"
echo "Analyzing: $CSV_FILE"
echo ""

# Extract data (skip header)
tail -n +2 "$CSV_FILE" | while IFS=',' read pwm rpm status; do
    echo "PWM: $pwm → RPM: $rpm ($status)"
done

echo ""
echo -e "${BLUE}=== Analysis & Recommendations ===${NC}"
echo ""

# Find minimum PWM where fan starts
min_running_pwm=$(tail -n +2 "$CSV_FILE" | awk -F',' '$2 > 50 {print $1; exit}')
max_rpm=$(tail -n +2 "$CSV_FILE" | awk -F',' '{print $2}' | sort -nr | head -1)

if [ -z "$min_running_pwm" ]; then
    echo -e "${RED}WARNING: Fan doesn't appear to run at any PWM level!${NC}"
    echo "Check that the kernel module is loaded and fan is connected."
    exit 1
fi

echo -e "${YELLOW}Minimum PWM (fan starts): $min_running_pwm${NC}"
echo "  → Recommendation: Set min_pwm to $(($min_running_pwm + 5)) (slightly above minimum for reliability)"
echo ""

echo -e "${YELLOW}Maximum RPM: $max_rpm${NC}"
echo "  → Fan can reach $max_rpm RPM at full speed"
echo ""

# Calculate PWM range
pwm_for_half_speed=$(tail -n +2 "$CSV_FILE" | \
    awk -F',' -v max="$max_rpm" '$2 >= max/2 && $2 <= max*0.6 {print $1; exit}')

if [ -n "$pwm_for_half_speed" ]; then
    echo -e "${YELLOW}PWM for ~50% speed: $pwm_for_half_speed${NC}"
    echo ""
fi

echo -e "${BLUE}=== Tuning Recommendations ===${NC}"
echo ""
echo "Current settings in temp_monitor.sh:"
echo "  min_pwm=60          # Adjust if your fan doesn't start reliably at this level"
echo "  hdd_threshold=35    # NVMe temp at which fan starts ramping"
echo "  sys_threshold=50    # CPU temp at which fan starts ramping"
echo ""

echo "Suggested adjustments based on this fan:"
echo ""
echo "1. Update min_pwm if needed:"
echo "   sudo sed -i 's/^min_pwm=60/min_pwm=$(($min_running_pwm + 5))/' /opt/asustor-fancontrol/bin/temp_monitor.sh"
echo ""

echo "2. If fan response is too slow, make curve more aggressive:"
echo "   Edit /opt/asustor-fancontrol/bin/temp_monitor.sh, line 216:"
echo "   Change: let hdd_desired_pwm=\$hdd_desired_pwm*10/18"
echo "   To:     let hdd_desired_pwm=\$hdd_desired_pwm*10/12  (more aggressive)"
echo "   Or:     let hdd_desired_pwm=\$hdd_desired_pwm*10/24  (more gentle)"
echo ""

echo "3. If fan response is too aggressive, make curve more gentle:"
echo "   (see option 2 above, use larger divisor)"
echo ""

echo "4. After changes, restart the service:"
echo "   sudo systemctl restart asustor-fancontrol-monitor.service"
echo ""

echo -e "${YELLOW}Next: Monitor fan under temperature load to verify behavior${NC}"
echo "   Watch in real-time: watch -n 1 'sensors | grep -E \"fan1|pwm1\"'"
