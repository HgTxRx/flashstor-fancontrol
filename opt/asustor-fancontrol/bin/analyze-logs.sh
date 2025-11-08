#!/bin/bash

# System statistics log analyzer
# Processes logs from log-system-stats.sh and provides analysis

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <log-file>"
    echo ""
    echo "Example: $0 /var/log/asustor-fancontrol/system-stats-20241107-231000.csv"
    exit 1
fi

LOG_FILE="$1"

# Verify file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}ERROR: Log file not found: $LOG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}=== System Statistics Analysis ===${NC}"
echo "Analyzing: $LOG_FILE"
echo ""

# Count samples
SAMPLES=$(tail -n +2 "$LOG_FILE" | wc -l)
echo -e "${YELLOW}Total samples: $SAMPLES${NC}"
echo ""

# Extract header
HEADER=$(head -1 "$LOG_FILE")
echo -e "${BLUE}Columns: $HEADER${NC}"
echo ""

# Analysis function for each column
analyze_column() {
    local col_name="$1"
    local col_num="$2"

    # Extract values
    VALUES=$(tail -n +2 "$LOG_FILE" | cut -d',' -f"$col_num" | grep -v '^$')

    if [ -z "$VALUES" ]; then
        echo "  No data"
        return
    fi

    # Calculate statistics
    MIN=$(echo "$VALUES" | sort -n | head -1)
    MAX=$(echo "$VALUES" | sort -n | tail -1)
    AVG=$(echo "$VALUES" | awk '{sum+=$1} END {printf "%.1f", sum/NR}')

    printf "  %-20s Min: %-6s Max: %-6s Avg: %-6s\n" "$col_name" "$MIN" "$MAX" "$AVG"
}

echo -e "${BLUE}=== Statistics ===${NC}"
echo ""

# PWM column 2
echo "PWM (0-255):"
analyze_column "PWM" 2
echo ""

# Fan RPM column 3
echo "Fan RPM:"
analyze_column "Fan RPM" 3
echo ""

# CPU Temp column 4
echo "CPU Temperature (°C):"
analyze_column "CPU Temp" 4
echo ""

# Board Temp column 5
echo "Board Temperature (°C):"
analyze_column "Board Temp" 5
echo ""

# NVMe temps starting at column 6
echo "NVMe Temperatures (°C):"
NUM_NVME=$(echo "$HEADER" | tr ',' '\n' | grep -c "^NVMe" || true)
for ((i=0; i<NUM_NVME; i++)); do
    col=$((6 + i))
    col_name="NVMe$((i+1))"
    analyze_column "$col_name" "$col"
done
echo ""

# Correlation analysis
echo -e "${BLUE}=== Correlation Analysis ===${NC}"
echo ""
echo "Checking how fan responds to temperature changes..."
echo ""

# Calculate PWM vs CPU temp correlation (simple)
PWM_VALUES=$(tail -n +2 "$LOG_FILE" | cut -d',' -f2)
CPU_VALUES=$(tail -n +2 "$LOG_FILE" | cut -d',' -f4)

PWM_AVG=$(echo "$PWM_VALUES" | awk '{sum+=$1} END {printf "%.1f", sum/NR}')
CPU_AVG=$(echo "$CPU_VALUES" | awk '{sum+=$1} END {printf "%.1f", sum/NR}')

# Simple correlation check
echo "PWM responds to CPU temperature:"
paste <(echo "$PWM_VALUES") <(echo "$CPU_VALUES") | \
    awk '{pwm_var+=($1-'$PWM_AVG')^2; cpu_var+=($2-'$CPU_AVG')^2; cov+=($1-'$PWM_AVG')*($2-'$CPU_AVG')}
         END {if(pwm_var>0 && cpu_var>0) corr=cov/sqrt(pwm_var*cpu_var); else corr=0; printf "  Correlation: %.2f\n", corr}'

echo ""

# Fan stability
echo "Fan stability (RPM variance):"
FAN_VALUES=$(tail -n +2 "$LOG_FILE" | cut -d',' -f3)
FAN_AVG=$(echo "$FAN_VALUES" | awk '{sum+=$1} END {printf "%.0f", sum/NR}')
FAN_STDDEV=$(echo "$FAN_VALUES" | awk -v avg="$FAN_AVG" '{sum+=($1-avg)^2} END {printf "%.0f", sqrt(sum/NR)}')
echo "  Average: $FAN_AVG RPM"
echo "  Std Dev: $FAN_STDDEV RPM"
if [ "$FAN_STDDEV" -lt 100 ]; then
    echo "  ${GREEN}✓ Very stable${NC}"
elif [ "$FAN_STDDEV" -lt 300 ]; then
    echo "  ${YELLOW}~ Moderately stable${NC}"
else
    echo "  ${RED}✗ High variance (fan hunting?)${NC}"
fi

echo ""
echo -e "${BLUE}=== Recommendations ===${NC}"
echo ""

# Check for fan hunting
SPEED_CHANGES=$(paste <(tail -n +2 "$LOG_FILE" | cut -d',' -f3 | head -n -1) \
                       <(tail -n +2 "$LOG_FILE" | cut -d',' -f3 | tail -n +2) | \
                awk -F' ' '{if($1!=$2) changes++} END {print changes+0}')
TOTAL_READINGS=$((SAMPLES - 1))
CHANGE_PERCENT=$((SPEED_CHANGES * 100 / TOTAL_READINGS))

echo "Fan speed changes: $SPEED_CHANGES out of $TOTAL_READINGS readings ($CHANGE_PERCENT%)"

if [ "$CHANGE_PERCENT" -gt 50 ]; then
    echo "${RED}WARNING: High fan speed changes detected (possible hunting)${NC}"
    echo "  Consider increasing delta thresholds in temp_monitor.sh"
    echo "  hdd_delta_threshold or sys_delta_threshold"
elif [ "$CHANGE_PERCENT" -lt 10 ]; then
    echo "${YELLOW}INFO: Low fan speed changes (fan may be unresponsive)${NC}"
    echo "  Consider lowering temperature thresholds"
else
    echo "${GREEN}✓ Normal fan responsiveness${NC}"
fi

echo ""
echo -e "${BLUE}=== Usage Examples ===${NC}"
echo ""
echo "View raw data:"
echo "  cat $LOG_FILE"
echo ""
echo "View formatted:"
echo "  column -t -s',' $LOG_FILE"
echo ""
echo "Extract specific columns:"
echo "  cut -d',' -f1,3,4 $LOG_FILE  # Time, Fan RPM, CPU Temp"
echo ""
echo "Graph with gnuplot:"
echo "  gnuplot"
echo "    > set datafile separator ','"
echo "    > plot '$LOG_FILE' using 0:3 with lines title 'Fan RPM'"
echo ""
