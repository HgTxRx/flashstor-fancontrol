#!/bin/bash

# System statistics logging script
# Collects PWM, fan RPM, and all system temperatures (including all NVMe drives)
# Logs to CSV file for analysis and graphing
# Can run continuously or as a one-shot

set -e

# Auto-detect hwmon paths (same as temp_monitor.sh)
HWMON_ACPI="/sys/class/hwmon/"`ls -lQ /sys/class/hwmon | grep -i thermal_zone0 | cut -d "\"" -f 2`
HWMON_IT87="/sys/class/hwmon/"`ls -lQ /sys/class/hwmon | grep -i it87 | cut -d "\"" -f 2`
HWMON_CORETEMP="/sys/class/hwmon/"`ls -lQ /sys/class/hwmon | grep -i coretemp | cut -d "\"" -f 2`

PWM_FILE="$HWMON_IT87/pwm1"
FAN_FILE="$HWMON_IT87/fan1_input"

LOG_DIR="/var/log/asustor-fancontrol"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/system-stats-$TIMESTAMP.csv"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default settings
INTERVAL=10  # seconds between logs
DURATION=0   # 0 = continuous, otherwise run for N seconds

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -f|--file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -i, --interval N   Log every N seconds (default: 10)"
            echo "  -d, --duration N   Run for N seconds total (default: 0 = continuous)"
            echo "  -f, --file PATH    Log file path (default: /var/log/asustor-fancontrol/system-stats-TIMESTAMP.csv)"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Log every 5 seconds for 5 minutes:"
            echo "  sudo $0 -i 5 -d 300"
            echo ""
            echo "  # Log every 10 seconds until Ctrl+C:"
            echo "  sudo $0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Verify hwmon devices were detected
if [ -z "$HWMON_IT87" ] || [ -z "$HWMON_CORETEMP" ] || [ -z "$HWMON_ACPI" ]; then
    echo -e "${RED}ERROR: Could not auto-detect hwmon devices${NC}"
    echo "Make sure asustor_it87 kernel module is loaded:"
    echo "  lsmod | grep asustor_it87"
    exit 1
fi

# Verify hwmon files exist
if [ ! -f "$PWM_FILE" ] || [ ! -f "$FAN_FILE" ]; then
    echo -e "${RED}ERROR: Cannot find pwm/fan files${NC}"
    echo "  PWM_FILE: $PWM_FILE"
    echo "  FAN_FILE: $FAN_FILE"
    echo "Check with: ls -la /sys/class/hwmon/hwmon*/pwm1"
    exit 1
fi

# Verify temperature files exist
if [ ! -f "$HWMON_CORETEMP/temp1_input" ] || [ ! -f "$HWMON_ACPI/temp1_input" ]; then
    echo -e "${RED}ERROR: Cannot find temperature sensor files${NC}"
    echo "  CORETEMP: $HWMON_CORETEMP/temp*_input"
    echo "  ACPI: $HWMON_ACPI/temp1_input"
    exit 1
fi

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Detect NVMe devices
declare -a NVME_DEVICES
i=0
for hwmon in /sys/class/hwmon/hwmon*/; do
    name=$(cat "$hwmon/name" 2>/dev/null || echo "")
    if [[ "$name" == nvme* ]]; then
        NVME_DEVICES[$i]="$hwmon"
        ((i++))
    fi
done

if [ ${#NVME_DEVICES[@]} -eq 0 ]; then
    echo -e "${YELLOW}WARNING: No NVMe devices found${NC}"
fi

# Build CSV header
HEADER="Timestamp,PWM,FanRPM,CPUTempC,BoardTempC"
for ((j=0; j<${#NVME_DEVICES[@]}; j++)); do
    HEADER="$HEADER,NVMe$((j+1))TempC"
done

# Create CSV file with header
echo "$HEADER" > "$LOG_FILE"

echo -e "${GREEN}=== System Statistics Logger ===${NC}"
echo "Logging to: $LOG_FILE"
echo "Interval: ${INTERVAL}s"
if [ "$DURATION" -eq 0 ]; then
    echo "Duration: Continuous (Ctrl+C to stop)"
else
    echo "Duration: ${DURATION}s"
fi
echo ""
echo -e "${YELLOW}Detected hwmon devices:${NC}"
echo "  IT87 (Fan): $HWMON_IT87"
echo "  CoreTemp (CPU): $HWMON_CORETEMP"
echo "  ACPI (Board): $HWMON_ACPI"
echo ""
echo -e "${YELLOW}NVMe devices detected: ${#NVME_DEVICES[@]}${NC}"
for ((j=0; j<${#NVME_DEVICES[@]}; j++)); do
    nvme_name=$(cat "${NVME_DEVICES[$j]}/name" 2>/dev/null || echo "Unknown")
    echo "  NVMe$((j+1)): $nvme_name"
done
echo ""
echo "Starting logging in 5 seconds..."
sleep 5

# Logging loop
START_TIME=$(date +%s)
COUNT=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    # Check if duration exceeded
    if [ "$DURATION" -gt 0 ] && [ "$ELAPSED" -ge "$DURATION" ]; then
        echo ""
        echo -e "${GREEN}Logging duration reached.${NC}"
        break
    fi

    # Get timestamp
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get PWM
    PWM=$(cat "$PWM_FILE")

    # Get fan RPM
    FAN_RPM=$(cat "$FAN_FILE")

    # Get CPU temp (highest core)
    CPU_TEMP=$(cat "$HWMON_CORETEMP/temp"*_input 2>/dev/null | sort -nr | head -1)
    CPU_TEMP=$((CPU_TEMP / 1000))

    # Get board temp
    BOARD_TEMP=$(cat "$HWMON_ACPI/temp1_input" 2>/dev/null)
    BOARD_TEMP=$((BOARD_TEMP / 1000))

    # Build data line
    DATA_LINE="$TIMESTAMP,$PWM,$FAN_RPM,$CPU_TEMP,$BOARD_TEMP"

    # Get NVMe temps (highest sensor from each drive)
    for ((j=0; j<${#NVME_DEVICES[@]}; j++)); do
        nvme_path="${NVME_DEVICES[$j]}"
        # Find highest temp sensor on this NVMe
        nvme_temp=$(cat "$nvme_path/temp"*_input 2>/dev/null | sort -nr | head -1)
        nvme_temp=$((nvme_temp / 1000))
        DATA_LINE="$DATA_LINE,$nvme_temp"
    done

    # Write to CSV
    echo "$DATA_LINE" >> "$LOG_FILE"

    # Display progress
    ((COUNT++))
    if [ $((COUNT % 6)) -eq 0 ]; then  # Display every 6 intervals (60 seconds at 10s interval)
        echo -ne "\r${GREEN}[${ELAPSED}s]${NC} Logged $COUNT samples | CPU: ${CPU_TEMP}°C | Board: ${BOARD_TEMP}°C | Fan: ${FAN_RPM}RPM (PWM: ${PWM})"
    fi

    # Wait for next interval
    sleep "$INTERVAL"
done

echo ""
echo ""
echo -e "${GREEN}=== Logging Complete ===${NC}"
echo "Total samples: $COUNT"
echo "Log file: $LOG_FILE"
echo ""
echo "View raw data:"
echo "  head $LOG_FILE"
echo "  tail $LOG_FILE"
echo ""
echo "Convert to graph-friendly format:"
echo "  column -t -s',' $LOG_FILE | less"
echo ""
echo "Analyze with gnuplot or similar:"
echo "  gnuplot -e \"set datafile separator ','; plot '$LOG_FILE' using 1:2 with lines title 'PWM'\""
