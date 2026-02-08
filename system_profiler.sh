#!/bin/bash

# System Profiler — Lightweight edition
# Produces system_profile.txt alongside this script
# Designed for minimal compute: reads each source once, avoids unnecessary subprocesses
# Works on Linux (x86, ARM), macOS, and other Unix-like systems

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/system_profile.txt"

# --- Cached reads: hit each source once ---
_uname=$(uname)
_uname_m=$(uname -m)
_uname_r=$(uname -r)

if [ "$_uname" = "Linux" ] && [ -f /proc/cpuinfo ]; then
    _cpuinfo=$(< /proc/cpuinfo)
fi

# --- ARM lookup tables ---

arm_core_name() {
    case "$1" in
        0xd01) echo "Cortex-A32" ;;
        0xd03) echo "Cortex-A53" ;;
        0xd04) echo "Cortex-A35" ;;
        0xd05) echo "Cortex-A55" ;;
        0xd07) echo "Cortex-A57" ;;
        0xd08) echo "Cortex-A72" ;;
        0xd09) echo "Cortex-A73" ;;
        0xd0a) echo "Cortex-A75" ;;
        0xd0b) echo "Cortex-A76" ;;
        0xd0c) echo "Neoverse-N1" ;;
        0xd0d) echo "Cortex-A77" ;;
        0xd0e) echo "Cortex-A76AE" ;;
        0xd40) echo "Neoverse-V1" ;;
        0xd41) echo "Cortex-A78" ;;
        0xd44) echo "Cortex-X1" ;;
        0xd46) echo "Cortex-A510" ;;
        0xd47) echo "Cortex-A710" ;;
        0xd48) echo "Cortex-X2" ;;
        0xd49) echo "Neoverse-N2" ;;
        0xd4d) echo "Cortex-A715" ;;
        0xd4e) echo "Cortex-X3" ;;
        0xd80) echo "Cortex-A520" ;;
        0xd81) echo "Cortex-A720" ;;
        0xd82) echo "Cortex-X4" ;;
        *)     echo "Unknown ($1)" ;;
    esac
}

arm_vendor_name() {
    case "$1" in
        0x41) echo "ARM" ;;
        0x42) echo "Broadcom" ;;
        0x43) echo "Cavium" ;;
        0x46) echo "Fujitsu" ;;
        0x48) echo "HiSilicon" ;;
        0x4e) echo "NVIDIA" ;;
        0x50) echo "APM" ;;
        0x51) echo "Qualcomm" ;;
        0x53) echo "Samsung" ;;
        0x56) echo "Marvell" ;;
        0x61) echo "Apple" ;;
        0x69) echo "Intel" ;;
        0xc0) echo "Ampere" ;;
        *)    echo "Unknown ($1)" ;;
    esac
}

# Helper: extract first matching field from cached cpuinfo
cpuinfo_field() {
    echo "$_cpuinfo" | grep -m1 "$1" | cut -d':' -f2 | sed 's/^ *//'
}

# --- Main output (piped to tee for file output) ---

main() {

echo "==========================================="
echo "System Profiler"
echo "Generated: $(date)"
echo "==========================================="

echo ""
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "System: $_uname"
echo "Kernel: $_uname_r"
echo "Architecture: $_uname_m"
if [ "$_uname" = "Linux" ]; then
    if command -v lsb_release &>/dev/null; then
        echo "Distribution: $(lsb_release -d | cut -f2)"
    elif [ -f /etc/os-release ]; then
        echo "Distribution: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    fi
fi

echo ""
echo "=== CPU Information ==="
if [ "$_uname" = "Darwin" ]; then
    echo "CPU Model: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
    echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')"
    echo "CPU Architecture: $_uname_m"
else
    if echo "$_cpuinfo" | grep -q "CPU part"; then
        # ARM processor
        if [ -f "/proc/device-tree/model" ]; then
            cpu_model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
        fi
        cpu_model="${cpu_model:-ARM Processor}"

        cpu_part_hex=$(cpuinfo_field "CPU part")
        cpu_impl_hex=$(cpuinfo_field "CPU implementer")
        cpu_arch_num=$(cpuinfo_field "CPU architecture")

        if [ -n "$cpu_part_hex" ]; then
            core_name=$(arm_core_name "$cpu_part_hex")
            vendor_name=$(arm_vendor_name "$cpu_impl_hex")
            cpu_model="$cpu_model ($core_name, $vendor_name, ARMv${cpu_arch_num})"
        fi
        echo "CPU Model: $cpu_model"
    else
        # x86/x64 processor
        cpu_model=$(cpuinfo_field "model name")
        echo "CPU Model: ${cpu_model:-Unknown}"
    fi

    echo "CPU Cores: $(nproc 2>/dev/null || echo 'Unknown')"
    echo "CPU Architecture: $_uname_m"

    # CPU frequency — awk replaces bc dependency
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        freq_khz=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        if [ -n "$freq_khz" ]; then
            echo "CPU Current Frequency: $(awk "BEGIN {printf \"%.2f GHz\", $freq_khz / 1000000}")"
        fi
    elif [ -n "$_cpuinfo" ]; then
        freq_mhz=$(cpuinfo_field "cpu MHz")
        if [ -n "$freq_mhz" ]; then
            echo "CPU Frequency: $(awk "BEGIN {printf \"%.2f GHz\", $freq_mhz / 1000}")"
        fi
    fi
fi

echo ""
echo "=== Memory Information ==="
if [ "$_uname" = "Darwin" ]; then
    echo "Total Memory: $(sysctl -n hw.memsize | awk '{printf "%.2f GB", $1/1024/1024/1024}')"
    free_pages=$(vm_stat | grep free | awk '{print $3}' | sed 's/\.//')
    page_size=$(pagesize)
    free_mem=$((free_pages * page_size))
    echo "Available Memory: $(echo "$free_mem" | awk '{printf "%.2f GB", $1/1024/1024/1024}')"
else
    echo "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Available Memory: $(free -h | awk '/^Mem:/ {print $7}')"
    echo "Used Memory: $(free -h | awk '/^Mem:/ {print $3}')"
fi

echo ""
echo "=== Storage Information ==="
echo "Disk Usage:"
df -h | grep -E "^/dev/" | head -5 | sed 's/^/  /'
if [ "$_uname" != "Darwin" ]; then
    echo "Mount Points:"
    mount | grep -E "^/dev/" | head -5 | sed 's/^/  /'
fi

echo ""
echo "=== Network Information ==="
if command -v ip &>/dev/null; then
    echo "Network Interfaces:"
    ip -o -4 addr show 2>/dev/null | awk '{split($4,a,"/"); print "  " $2 ": " a[1]}'
elif command -v ifconfig &>/dev/null; then
    echo "Network Interfaces:"
    ifconfig 2>/dev/null | awk '/^[a-zA-Z]/{iface=$1; sub(/:$/,"",iface)} /inet /{print "  " iface ": " $2}'
else
    echo "IP Addresses: $(hostname -I 2>/dev/null || echo 'Not available')"
fi

echo ""
echo "=== Process and Load Information ==="
if [ "$_uname" = "Darwin" ]; then
    echo "Load Average: $(sysctl -n vm.loadavg | tr -d '{}')"
    echo "Running Processes: $(ps -axc | wc -l | sed 's/ *//')"
else
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Running Processes: $(ps -eo stat | grep -c '^[RD]')"
    echo "Total Processes: $(ps aux | wc -l)"
fi

echo ""
echo "=== Uptime Information ==="
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
if [ "$_uname" = "Linux" ]; then
    echo "Boot Time: $(who -b | awk '{print $3, $4}')"
fi

echo ""
echo "=== Temperature Information ==="
temp_found=false

if [ -d "/sys/class/thermal" ]; then
    for zone in /sys/class/thermal/thermal_zone*/; do
        [ -r "$zone/type" ] && [ -r "$zone/temp" ] || continue
        zone_type=$(< "$zone/type")
        zone_temp=$(< "$zone/temp")
        # Guard: only convert if numeric and in millidegrees
        if [ -n "$zone_temp" ] && [ "$zone_temp" -gt 1000 ] 2>/dev/null; then
            zone_temp=$(awk "BEGIN {printf \"%.1f\", $zone_temp / 1000}")
        fi
        echo "  $zone_type: ${zone_temp}C"
        temp_found=true
    done
fi

if command -v vcgencmd &>/dev/null; then
    soc_temp=$(vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2)
    if [ -n "$soc_temp" ]; then
        echo "  SoC Temperature: $soc_temp"
        temp_found=true
    fi
fi

if [ "$_uname" = "Darwin" ]; then
    if command -v smcutil &>/dev/null; then
        cpu_temp=$(smcutil -k TCSA 2>/dev/null | awk '{print $NF}')
        [ -n "$cpu_temp" ] && echo "  CPU Temperature: ${cpu_temp}C" && temp_found=true
    elif command -v osx-cpu-temp &>/dev/null; then
        cpu_temp=$(osx-cpu-temp 2>/dev/null)
        [ -n "$cpu_temp" ] && echo "  CPU Temperature: $cpu_temp" && temp_found=true
    fi
fi

[ "$temp_found" = false ] && echo "  Temperature: Not available"

echo ""
echo "=== GPU Information ==="
gpu_found=false

# NVIDIA
if command -v nvidia-smi &>/dev/null; then
    gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>&1)
    if [ $? -eq 0 ] && [ -n "$gpu_info" ] && ! echo "$gpu_info" | grep -q "failed\|error\|cannot"; then
        echo "NVIDIA GPUs: $(echo "$gpu_info" | wc -l) detected"
        echo "$gpu_info" | sed 's/^/  /'
        gpu_found=true
    fi
fi

# AMD
if command -v rocm-smi &>/dev/null; then
    if rocm-smi --showdriverversion &>/dev/null; then
        echo "AMD GPU(s) detected"
        gpu_found=true
    fi
fi

# Intel — verify via PCI vendor ID 0x8086, not just DRM card count
if [ -d "/sys/class/drm" ]; then
    for card_vendor in /sys/class/drm/card[0-9]*/device/vendor; do
        [ -r "$card_vendor" ] || continue
        if [ "$(< "$card_vendor")" = "0x8086" ]; then
            echo "Intel Integrated GPU detected"
            gpu_found=true
            break
        fi
    done
fi

# Raspberry Pi VideoCore
if [ -f "/proc/device-tree/model" ] && grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    if command -v vcgencmd &>/dev/null; then
        gpu_mem=$(vcgencmd get_mem gpu 2>/dev/null | grep -o "[0-9]*M" || echo "Unknown")
        echo "VideoCore GPU: Memory=$gpu_mem"
        gpu_found=true
    fi
fi

# macOS
if [ "$_uname" = "Darwin" ]; then
    gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chip|Processor|Memory" | head -6)
    if [ -n "$gpu_info" ]; then
        echo "GPU(s):"
        echo "$gpu_info" | sed 's/^/  /'
        gpu_found=true
    fi
fi

[ "$gpu_found" = false ] && echo "GPU: Not detected"

echo ""
echo "=== Power Information ==="
power_found=false

if [ -d "/sys/class/power_supply" ]; then
    for batt in /sys/class/power_supply/BAT*/capacity; do
        if [ -r "$batt" ]; then
            echo "Battery Level: $(< "$batt")%"
            power_found=true
        fi
    done
fi

if [ "$_uname" = "Darwin" ] && command -v pmset &>/dev/null; then
    batt_info=$(pmset -g batt 2>/dev/null | grep -o "[0-9]*%" | head -1)
    if [ -n "$batt_info" ]; then
        echo "Battery Level: $batt_info"
        power_found=true
    fi
fi

[ "$power_found" = false ] && echo "Power: No battery detected"

echo ""
echo "==========================================="
echo "System profiling complete."
echo "==========================================="

}

# Run main, write to both stdout and file
main 2>&1 | tee "$OUTPUT_FILE"
