#!/bin/bash

# Fan PWM to RPM calibration script
# Tests different PWM values and records the resulting fan RPM
# Helps re-tune fan control curves after fan replacement

set -e

# Auto-detect hwmon paths (same as temp_monitor.sh)
HWMON_IT87="/sys/class/hwmon/"`ls -lQ /sys/class/hwmon | grep -i it87 | cut -d "\"" -f 2`

PWM_FILE="$HWMON_IT87/pwm1"
FAN_FILE="$HWMON_IT87/fan1_input"
OUTPUT_FILE="/tmp/fan-calibration-$(date +%Y%m%d-%H%M%S).csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Verify hwmon device was detected
if [ -z "$HWMON_IT87" ]; then
    echo -e "${RED}ERROR: Could not auto-detect it8625 hwmon device${NC}"
    echo "Make sure asustor_it87 kernel module is loaded:"
    echo "  lsmod | grep asustor_it87"
    exit 1
fi

# Verify hwmon files exist
if [ ! -f "$PWM_FILE" ] || [ ! -f "$FAN_FILE" ]; then
    echo -e "${RED}ERROR: Cannot find pwm/fan files${NC}"
    echo "  Detected: $HWMON_IT87"
    echo "  PWM_FILE: $PWM_FILE"
    echo "  FAN_FILE: $FAN_FILE"
    exit 1
fi

echo -e "${GREEN}=== Asustor Fan PWM to RPM Calibration ===${NC}"
echo "Detected it8625 device at: $HWMON_IT87"
echo "This script will test different PWM values and record fan RPM."
echo "Output will be saved to: $OUTPUT_FILE"
echo ""
echo -e "${YELLOW}CAUTION: This will change your fan speed during testing.${NC}"
echo -e "${YELLOW}Press Ctrl+C to cancel or Enter to continue...${NC}"
read

# Create CSV header
echo "PWM,RPM,Notes" > "$OUTPUT_FILE"

# Test PWM values
declare -a PWM_VALUES=(0 20 40 60 80 100 120 140 160 180 200 220 240 255)

echo -e "\n${GREEN}Starting calibration...${NC}"
echo "Waiting 30 seconds for fan to stabilize before first test..."
sleep 30
echo ""

for pwm in "${PWM_VALUES[@]}"; do
    echo -n "Testing PWM $pwm... "

    # Set PWM value
    echo "$pwm" > "$PWM_FILE"

    # Wait for fan to stabilize (10 seconds for mechanical response)
    sleep 10

    # Read fan RPM
    rpm=$(cat "$FAN_FILE")

    # Determine if fan is running
    if [ "$rpm" -lt 50 ]; then
        status="Not running"
    else
        status="Running"
    fi

    echo -e "${GREEN}$rpm RPM${NC} ($status)"

    # Append to CSV
    echo "$pwm,$rpm,$status" >> "$OUTPUT_FILE"
done

# Return fan to safe state (minimum PWM)
echo ""
echo -n "Returning fan to minimum speed (PWM 60)... "
echo "60" > "$PWM_FILE"
sleep 10
rpm=$(cat "$FAN_FILE")
echo -e "${GREEN}Done ($rpm RPM)${NC}"

echo ""
echo -e "${GREEN}=== Calibration Complete ===${NC}"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Data for analysis:"
cat "$OUTPUT_FILE"
echo ""
echo "To view in a spreadsheet:"
echo "  cat $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the PWM-to-RPM relationship"
echo "  2. Determine minimum safe PWM (fan must spin reliably)"
echo "  3. Adjust min_pwm in temp_monitor.sh if needed"
echo "  4. Re-test fan control under temperature load"
