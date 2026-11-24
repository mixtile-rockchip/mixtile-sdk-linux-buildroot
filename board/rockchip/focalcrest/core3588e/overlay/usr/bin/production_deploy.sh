#!/bin/bash

set -euo pipefail

LOG_DIR="${LOG_DIR:-/userdata/production_log}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/production.log}"
TOOL_DIR="${TOOL_DIR:-/root/ProductionTool}"

EXPECTED_COMPATIBLE="${EXPECTED_COMPATIBLE:-core3588e}"

CONFIG_FILES="configs.json product_configs.json start.sh"
CONFIG_DIR=""

USB_MOUNT_CANDIDATES="${USB_MOUNT_CANDIDATES:-/mnt/udisk /media/udisk0 /media/udisk1 /media/udisk2 /media/udisk3}"
USB_BLOCK_GLOB="${USB_BLOCK_GLOB:-/sys/block/sd*}"

CONFIG_MEDIA_WAIT_SEC="${CONFIG_MEDIA_WAIT_SEC:-15}"
CONFIG_MEDIA_PRESENCE_WAIT_SEC="${CONFIG_MEDIA_PRESENCE_WAIT_SEC:-10}"
CONFIG_MEDIA_POLL_SEC="${CONFIG_MEDIA_POLL_SEC:-0.5}"

ENABLE_CPU_MAX_FREQ="${ENABLE_CPU_MAX_FREQ:-1}"
CPUFREQ_POLICY_GLOB="${CPUFREQ_POLICY_GLOB:-/sys/devices/system/cpu/cpufreq/policy*}"

BURNIN_ROOT_DIR="${BURNIN_ROOT_DIR:-$LOG_DIR/burnin}"
BURNIN_CURRENT_DIR_NAME="${BURNIN_CURRENT_DIR_NAME:-current}"
STATUS_LED_TRIGGER="${STATUS_LED_TRIGGER:-/sys/class/leds/sys_status_led/trigger}"
STATUS_LED_BRIGHTNESS="${STATUS_LED_BRIGHTNESS:-/sys/class/leds/sys_status_led/brightness}"
STATUS_LED_MANAGED_BY_SCRIPT="${STATUS_LED_MANAGED_BY_SCRIPT:-1}"
STATUS_LED_BLINK_ON_SEC="${STATUS_LED_BLINK_ON_SEC:-1}"
STATUS_LED_BLINK_OFF_SEC="${STATUS_LED_BLINK_OFF_SEC:-1}"

STRESS_NG_BIN="${STRESS_NG_BIN:-stress-ng}"
MEMTESTER_BIN="${MEMTESTER_BIN:-memtester}"
GLMARK2_BIN="${GLMARK2_BIN:-glmark2-es2-wayland}"
DD_BIN="${DD_BIN:-dd}"
MD5SUM_BIN="${MD5SUM_BIN:-md5sum}"
TASKSET_BIN="${TASKSET_BIN:-taskset}"
GPU_TASKSET="${GPU_TASKSET:-4-7}"
BURNIN_CPU_LOAD_PERCENT="${BURNIN_CPU_LOAD_PERCENT:-75}"
BURNIN_CPU_TIMEOUT="${BURNIN_CPU_TIMEOUT:-0s}"

MONITOR_INTERVAL_SEC="${MONITOR_INTERVAL_SEC:-30}"
SUPERVISOR_POLL_INTERVAL_SEC="${SUPERVISOR_POLL_INTERVAL_SEC:-2}"
WARN_TEMP_MC="${WARN_TEMP_MC:-90000}"
FAIL_TEMP_MC="${FAIL_TEMP_MC:-95000}"
FAIL_TEMP_SAMPLES="${FAIL_TEMP_SAMPLES:-10}"
DDR_RESERVE_PERCENT="${DDR_RESERVE_PERCENT:-15}"
DDR_RESERVE_MIN_MB="${DDR_RESERVE_MIN_MB:-256}"
DDR_RESERVE_MAX_MB="${DDR_RESERVE_MAX_MB:-512}"
DDR_TEST_MAX_PERCENT="${DDR_TEST_MAX_PERCENT:-85}"
DDR_MIN_TEST_MB="${DDR_MIN_TEST_MB:-64}"
EMMC_MIN_FREE_MB="${EMMC_MIN_FREE_MB:-1024}"
EMMC_TARGET_SIZE_MB="${EMMC_TARGET_SIZE_MB:-512}"
EMMC_MIN_TEST_SIZE_MB="${EMMC_MIN_TEST_SIZE_MB:-64}"
EMMC_COPY_DIR_COUNT="${EMMC_COPY_DIR_COUNT:-5}"
EMMC_MAX_CYCLES="${EMMC_MAX_CYCLES:-}"
EMMC_BLOCK_DEVICE="${EMMC_BLOCK_DEVICE:-/dev/mmcblk0}"
EMMC_DATASET_SIZE_PER_GB_MB="${EMMC_DATASET_SIZE_PER_GB_MB:-2}"
EMMC_TARGET_WRITE_PERCENT="${EMMC_TARGET_WRITE_PERCENT:-50}"
EMMC_TARGET_WRITE_MIN_GB="${EMMC_TARGET_WRITE_MIN_GB:-8}"
EMMC_TARGET_WRITE_MAX_GB="${EMMC_TARGET_WRITE_MAX_GB:-64}"
EMMC_FILE_MIN_KB="${EMMC_FILE_MIN_KB:-512}"
EMMC_FILE_MAX_KB="${EMMC_FILE_MAX_KB:-3456}"
EMMC_CACHE_DROP_SLEEP_SEC="${EMMC_CACHE_DROP_SLEEP_SEC:-5}"

AGING_MODE_GPIO="${AGING_MODE_GPIO:-129}"
FAN_PWR_TARGET_LOW="${FAN_PWR_TARGET_LOW:-70000}"
FAN_PWR_TARGET_HIGH="${FAN_PWR_TARGET_HIGH:-75000}"
FAN_PWR_CONTROL_INTERVAL="${FAN_PWR_CONTROL_INTERVAL:-10}"
SOM_MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if printf '%s\n' "$SOM_MODEL" | grep -Eiq 'v2'; then
    FAN_PWR_GPIO="${FAN_PWR_GPIO:-124}"
else
    FAN_PWR_GPIO="${FAN_PWR_GPIO:-118}"
fi
AGING_LED_HWMON_GLOB="${AGING_LED_HWMON_GLOB:-/sys/devices/platform/pwm-fan/hwmon/hwmon*}"
AGING_LED_ON_VALUE="${AGING_LED_ON_VALUE:-0}"
AGING_LED_OFF_VALUE="${AGING_LED_OFF_VALUE:-255}"
BOARD_VARIANT="${BOARD_VARIANT:-core3588e}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

RESOLVED_STRESS_NG_BIN=""
RESOLVED_MEMTESTER_BIN=""
RESOLVED_GLMARK2_BIN=""
RESOLVED_DD_BIN=""
RESOLVED_MD5SUM_BIN=""
RESOLVED_TASKSET_BIN=""

BURNIN_RUN_DIR=""
BURNIN_STATUS_FILE=""
WATCHDOG_STATUS_FILE=""
BURNIN_MONITOR_FILE=""
BURNIN_DMESG_MARKER_FILE=""
BURNIN_DMESG_DELTA_FILE=""
BURNIN_STOP_FLAG=""
CPU_LOG_FILE=""
GPU_LOG_FILE=""
DDR_LOG_FILE=""
DDR_STATUS_FILE=""
EMMC_LOG_FILE=""
EMMC_STATUS_FILE=""
EMMC_WORK_DIR=""
EMMC_SOURCE_DIR=""
EMMC_SOURCE_MD5_FILE=""
EMMC_VERIFY_ROOT_DIR=""
EMMC_VERIFY_MD5_DIR=""


mkdir -p "$LOG_DIR"

log_sync() {
    sync
}

if [[ "${PRODUCTION_DEPLOY_NO_REDIRECT:-0}" != "1" ]]; then
    exec > >(stdbuf -oL -eL tee -a "$LOG_FILE") 2>&1
fi

xlog() {
    local level="$1"
    shift
    local msg="$*"
    local ts

    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg" >&2
    log_sync
}

read_compatible_strings() {
    local path=""

    if [[ -n "${DEVICE_TREE_COMPATIBLE_OVERRIDE:-}" ]]; then
        printf '%s\n' "$DEVICE_TREE_COMPATIBLE_OVERRIDE"
        return 0
    fi

    for path in /proc/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
        if [[ -r "$path" ]]; then
            tr '\0' '\n' < "$path"
            return 0
        fi
    done

    return 1
}

assert_expected_board() {
    local compatible_strings=""

    compatible_strings="$(read_compatible_strings 2>/dev/null || true)"
    if [[ -z "$compatible_strings" ]]; then
        xlog "ERROR" "Cannot read the device tree compatible string"
        return 1
    fi

    if ! printf '%s\n' "$compatible_strings" | grep -Eiq "$EXPECTED_COMPATIBLE"; then
        xlog "ERROR" "This build is for '$EXPECTED_COMPATIBLE' but the board reports:" \
            "$(printf '%s' "$compatible_strings" | tr '\n' ' ')." \
            "Wrong overlay for this board - refusing to run."
        return 1
    fi

    xlog "INFO" "Board matches '$EXPECTED_COMPATIBLE'"
}

set_cpu_max_freq() {
    local policy_path="$1"
    local max_freq=""
    local cur_freq=""
    local available_governors=""

    [[ -d "$policy_path" ]] || return 0

    if [[ -r "$policy_path/scaling_max_freq" ]]; then
        max_freq="$(cat "$policy_path/scaling_max_freq" 2>/dev/null || true)"
    fi
    if [[ ! "$max_freq" =~ ^[0-9]+$ ]] && [[ -r "$policy_path/scaling_available_frequencies" ]]; then
        max_freq="$(awk '{print $NF}' "$policy_path/scaling_available_frequencies" 2>/dev/null || true)"
    fi
    if [[ ! "$max_freq" =~ ^[0-9]+$ ]] && [[ -r "$policy_path/cpuinfo_max_freq" ]]; then
        max_freq="$(cat "$policy_path/cpuinfo_max_freq" 2>/dev/null || true)"
    fi

    if [[ ! "$max_freq" =~ ^[0-9]+$ ]]; then
        xlog "WARN" "Unable to determine max frequency for ${policy_path##*/}"
        return 0
    fi

    available_governors="$(cat "$policy_path/scaling_available_governors" 2>/dev/null || true)"
    if [[ -w "$policy_path/scaling_governor" ]]; then
        if [[ "$available_governors" == *"userspace"* ]] && [[ -w "$policy_path/scaling_setspeed" ]]; then
            echo userspace > "$policy_path/scaling_governor" 2>/dev/null || xlog "WARN" "Failed to set userspace governor for ${policy_path##*/}"
            echo "$max_freq" > "$policy_path/scaling_setspeed" 2>/dev/null || xlog "WARN" "Failed to set scaling_setspeed for ${policy_path##*/}"
        elif [[ "$available_governors" == *"performance"* ]]; then
            echo performance > "$policy_path/scaling_governor" 2>/dev/null || xlog "WARN" "Failed to set performance governor for ${policy_path##*/}"
        fi
    fi

    if [[ -w "$policy_path/scaling_max_freq" ]]; then
        echo "$max_freq" > "$policy_path/scaling_max_freq" 2>/dev/null || xlog "WARN" "Failed to set scaling_max_freq for ${policy_path##*/}"
    fi

    cur_freq="$(cat "$policy_path/scaling_cur_freq" 2>/dev/null || true)"
    if [[ "$cur_freq" =~ ^[0-9]+$ ]]; then
        xlog "INFO" "CPU freq policy:${policy_path##*/} target=${max_freq} current=${cur_freq} KHz"
    else
        xlog "WARN" "Unable to read current frequency for ${policy_path##*/}"
    fi
}

set_all_cpu_max_freq() {
    local policy_path=""

    xlog "INFO" "Setting all CPU policies to maximum frequency"
    for policy_path in $CPUFREQ_POLICY_GLOB; do
        [[ -d "$policy_path" ]] || continue
        set_cpu_max_freq "$policy_path"
    done
}

poll_count_for() {
    awk -v total="$1" -v step="$CONFIG_MEDIA_POLL_SEC" \
        'BEGIN { n = (step > 0) ? int(total / step) : 0; print (n > 0) ? n : 0 }'
}

config_files_present() {
    local dir="$1"
    local file_name=""

    for file_name in $CONFIG_FILES; do
        [[ -f "$dir/$file_name" && -r "$dir/$file_name" ]] || return 1
    done
    return 0
}

usb_block_device_present() {
    local dev=""

    for dev in $USB_BLOCK_GLOB; do
        [[ -e "$dev" ]] && return 0
    done
    return 1
}

wait_for_usb_block_device() {
    local loops=0 i=0

    if usb_block_device_present; then
        return 0
    fi

    loops="$(poll_count_for "$CONFIG_MEDIA_PRESENCE_WAIT_SEC")"
    if (( loops == 0 )); then
        return 1
    fi

    xlog "INFO" "No USB block device yet;" \
        "waiting up to ${CONFIG_MEDIA_PRESENCE_WAIT_SEC}s for enumeration"
    for (( i = 0; i < loops; i++ )); do
        sleep "$CONFIG_MEDIA_POLL_SEC"
        if usb_block_device_present; then
            xlog "INFO" "USB block device appeared after $((i + 1)) poll(s)"
            return 0
        fi
    done

    return 1
}

find_config_dir() {
    local mp="" real_mp="" scanned=" " mounted_seen=0

    for mp in $USB_MOUNT_CANDIDATES; do
        [[ -e "$mp" ]] || continue

        real_mp="$(realpath "$mp" 2>/dev/null || true)"
        [[ -n "$real_mp" ]] || continue
        [[ "$scanned" == *" $real_mp "* ]] && continue
        scanned="$scanned$real_mp "

        mountpoint -q "$real_mp" || continue
        mounted_seen=1

        if config_files_present "$real_mp"; then
            printf '%s\n' "$real_mp"
            return 0
        fi
        xlog "INFO" "$real_mp is mounted but has no config file set, skipping"
    done

    if (( mounted_seen == 0 )); then
        xlog "ERROR" "No USB storage mounted under any of: $USB_MOUNT_CANDIDATES;" \
            "usbmount only mounts a partition carrying a recognisable filesystem"
        return 5
    fi

    xlog "ERROR" "USB storage is mounted but none of$scanned" \
        "holds all of: $CONFIG_FILES"
    return 20
}

wait_for_config_dir() {
    local loops=0 i=0 dir=""

    loops="$(poll_count_for "$CONFIG_MEDIA_WAIT_SEC")"

    for (( i = 0; i <= loops; i++ )); do
        if dir="$(find_config_dir 2>/dev/null)"; then
            if (( i > 0 )); then
                xlog "INFO" "USB config media became usable after $i poll(s)"
            fi
            printf '%s\n' "$dir"
            return 0
        fi
        if (( i == 0 && loops > 0 )); then
            xlog "INFO" "Waiting up to ${CONFIG_MEDIA_WAIT_SEC}s for USB config media to be mounted"
        fi
        if (( i < loops )); then
            sleep "$CONFIG_MEDIA_POLL_SEC"
        fi
    done

    find_config_dir >/dev/null || true
    if (( loops > 0 )); then
        xlog "ERROR" "USB config media did not become usable within ${CONFIG_MEDIA_WAIT_SEC}s"
    fi
    return 5
}

set_status_led_default_on() {
    if [[ "$STATUS_LED_MANAGED_BY_SCRIPT" != "1" ]]; then
        return 0
    fi
    xlog "INFO" "Setting status LED to default-on"
    echo "default-on" > "$STATUS_LED_TRIGGER" 2>/dev/null || xlog "WARN" "Failed to set $STATUS_LED_TRIGGER to default-on"
}

set_status_led_manual_control() {
    if [[ "$STATUS_LED_MANAGED_BY_SCRIPT" != "1" ]]; then
        return 0
    fi
    echo "none" > "$STATUS_LED_TRIGGER" 2>/dev/null || xlog "WARN" "Failed to set $STATUS_LED_TRIGGER to none"
}

set_status_led_brightness() {
    local value="$1"

    if [[ "$STATUS_LED_MANAGED_BY_SCRIPT" != "1" ]]; then
        return 0
    fi
    echo "$value" > "$STATUS_LED_BRIGHTNESS" 2>/dev/null || xlog "WARN" "Failed to set $STATUS_LED_BRIGHTNESS to $value"
}

run_status_led_blink_loop() {
    trap 'set_status_led_brightness 1; exit 0' TERM INT

    set_status_led_manual_control
    while true; do
        set_status_led_brightness 1
        sleep "$STATUS_LED_BLINK_ON_SEC"
        set_status_led_brightness 0
        sleep "$STATUS_LED_BLINK_OFF_SEC"
    done
}

cleanup() {
    return 0
}

trap cleanup EXIT

write_status_file() {
    local file_path="$1"
    local status="$2"
    local reason="$3"

    shift 3
    mkdir -p "$(dirname "$file_path")"
    {
        printf 'STATUS=%q\n' "$status"
        printf 'REASON=%q\n' "$reason"
        printf 'UPDATED_AT=%q\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        while (( "$#" >= 2 )); do
            printf '%s=%q\n' "$1" "$2"
            shift 2
        done
    } > "$file_path"
    log_sync
}

load_status_file() {
    local file_path="$1"

    STATUS=""
    REASON=""
    UPDATED_AT=""
    if [[ -f "$file_path" ]]; then
        # shellcheck disable=SC1090
        source "$file_path"
    fi
}

ensure_status_terminal() {
    local file_path="$1"
    local desired_status="$2"
    local reason="$3"

    if [[ ! -f "$file_path" ]]; then
        write_status_file "$file_path" "$desired_status" "$reason"
        return 0
    fi

    load_status_file "$file_path"
    if [[ -z "${STATUS:-}" || "${STATUS:-}" == "RUNNING" ]]; then
        write_status_file "$file_path" "$desired_status" "$reason"
    fi
}

resolve_required_binary() {
    local binary_name="$1"
    local resolved=""

    if [[ "$binary_name" == */* ]]; then
        resolved="$binary_name"
    else
        resolved="$(command -v "$binary_name" || true)"
    fi

    if [[ -z "$resolved" || ! -x "$resolved" ]]; then
        return 1
    fi

    printf '%s\n' "$resolved"
}

kill_pid_if_running() {
    local pid="${1:-}"
    local name="${2:-process}"

    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    xlog "INFO" "Stopping $name (pid $pid)"
    kill "$pid" 2>/dev/null || true
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        xlog "WARN" "$name (pid $pid) did not stop after SIGTERM, sending SIGKILL"
        kill -9 "$pid" 2>/dev/null || true
    fi
}

append_command_output() {
    local output_file="$1"
    local log_file="$2"
    local rc="$3"
    local line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$log_file"
    done < "$output_file"
    printf '[%s] command_rc=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$rc" >> "$log_file"
}

extract_hash_value() {
    local text="$1"

    printf '%s\n' "$text" | awk '{print $1}'
}

format_temp_c() {
    local temp_mc="$1"

    awk -v value="$temp_mc" 'BEGIN { printf "%.3f", value / 1000 }'
}

read_optional_int_file() {
    local file_path="$1"
    local value=""

    value="$(cat "$file_path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    else
        printf '0\n'
    fi
}

read_thermal_temp_mc() {
    local zone_type="$1"
    local zone=""

    for zone in /sys/class/thermal/thermal_zone*; do
        [[ -d "$zone" ]] || continue
        if [[ "$(cat "$zone/type" 2>/dev/null || true)" == "$zone_type" ]]; then
            cat "$zone/temp" 2>/dev/null || echo 0
            return 0
        fi
    done

    echo 0
}
setup_burnin_paths() {
    BURNIN_RUN_DIR="$BURNIN_ROOT_DIR/$BURNIN_CURRENT_DIR_NAME"
    BURNIN_STATUS_FILE="$BURNIN_RUN_DIR/burnin.status"
    WATCHDOG_STATUS_FILE="$BURNIN_RUN_DIR/watchdog.status"
    BURNIN_MONITOR_FILE="$BURNIN_RUN_DIR/monitor.csv"
    BURNIN_DMESG_MARKER_FILE="$BURNIN_RUN_DIR/dmesg_lines.count"
    BURNIN_DMESG_DELTA_FILE="$BURNIN_RUN_DIR/dmesg.delta"
    BURNIN_STOP_FLAG="$BURNIN_RUN_DIR/stop.request"
    CPU_LOG_FILE="$BURNIN_RUN_DIR/cpu.log"
    GPU_LOG_FILE="$BURNIN_RUN_DIR/gpu.log"
    DDR_LOG_FILE="$BURNIN_RUN_DIR/ddr.log"
    DDR_STATUS_FILE="$BURNIN_RUN_DIR/ddr.status"
    EMMC_LOG_FILE="$BURNIN_RUN_DIR/emmc.log"
    EMMC_STATUS_FILE="$BURNIN_RUN_DIR/emmc.status"
    EMMC_WORK_DIR="$BURNIN_RUN_DIR/emmc-work"
    EMMC_SOURCE_DIR="$EMMC_WORK_DIR/source-data"
    EMMC_SOURCE_MD5_FILE="$EMMC_WORK_DIR/source.md5"
    EMMC_VERIFY_ROOT_DIR="$EMMC_WORK_DIR/verify-data"
    EMMC_VERIFY_MD5_DIR="$EMMC_WORK_DIR/verify-md5"

    case "$BURNIN_ROOT_DIR" in
        ""|"/"|"/userdata"|"/userdata/production_log")
            xlog "ERROR" "Refusing to reset unsafe burn-in root dir: $BURNIN_ROOT_DIR"
            return 1
            ;;
    esac

    mkdir -p "$BURNIN_ROOT_DIR"
    find "$BURNIN_ROOT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    mkdir -p "$BURNIN_RUN_DIR" "$EMMC_WORK_DIR"
}

record_monitor_header() {
    if [[ -f "$BURNIN_MONITOR_FILE" ]]; then
        return 0
    fi

    printf 'timestamp,phase,elapsed_s,soc_c,bigcore0_c,bigcore1_c,gpu_c,dmc_hz,gpu_hz,policy0_hz,policy4_hz,policy6_hz,root_used_pct,dmesg_error_count\n' > "$BURNIN_MONITOR_FILE"
    log_sync
}

record_monitor_sample() {
    local phase="$1"
    local elapsed_s="$2"
    local dmesg_error_count="$3"
    local soc_mc=""
    local big0_mc=""
    local big1_mc=""
    local gpu_mc=""
    local dmc_hz=""
    local gpu_hz=""
    local policy0_hz=""
    local policy4_hz=""
    local policy6_hz=""
    local root_used_pct=""

    soc_mc="$(read_thermal_temp_mc "soc-thermal")"
    big0_mc="$(read_thermal_temp_mc "bigcore0-thermal")"
    big1_mc="$(read_thermal_temp_mc "bigcore1-thermal")"
    gpu_mc="$(read_thermal_temp_mc "gpu-thermal")"
    dmc_hz="$(read_optional_int_file /sys/class/devfreq/dmc/cur_freq)"
    gpu_hz="$(read_optional_int_file /sys/class/devfreq/fb000000.gpu/cur_freq)"
    policy0_hz="$(read_optional_int_file /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)"
    policy4_hz="$(read_optional_int_file /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)"
    policy6_hz="$(read_optional_int_file /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq)"
    root_used_pct="$(df -P / | awk 'NR==2 { gsub("%", "", $5); print $5 }')"
    if [[ -z "$root_used_pct" ]]; then
        root_used_pct="0"
    fi

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
        "$phase" \
        "$elapsed_s" \
        "$(format_temp_c "$soc_mc")" \
        "$(format_temp_c "$big0_mc")" \
        "$(format_temp_c "$big1_mc")" \
        "$(format_temp_c "$gpu_mc")" \
        "$dmc_hz" \
        "$gpu_hz" \
        "$policy0_hz" \
        "$policy4_hz" \
        "$policy6_hz" \
        "$root_used_pct" \
        "$dmesg_error_count" >> "$BURNIN_MONITOR_FILE"
    log_sync
}

init_dmesg_marker() {
    local current_lines=0

    current_lines="$(dmesg | wc -l | tr -d ' ')"
    printf '%s\n' "$current_lines" > "$BURNIN_DMESG_MARKER_FILE"
    : > "$BURNIN_DMESG_DELTA_FILE"
    log_sync
}

get_emmc_host_name() {
    local block_name=""
    local host_path=""

    if [[ -n "${EMMC_HOST_NAME_OVERRIDE:-}" ]]; then
        printf '%s\n' "$EMMC_HOST_NAME_OVERRIDE"
        return 0
    fi

    block_name="${EMMC_BLOCK_DEVICE##*/}"
    host_path="$(readlink -f "/sys/class/block/$block_name/device/.." 2>/dev/null || true)"
    if [[ -z "$host_path" ]]; then
        return 1
    fi

    basename "$host_path"
}

scan_new_dmesg_errors() {
    local previous_lines=0
    local current_lines=0
    local tmp_file="${BURNIN_DMESG_DELTA_FILE}.current"

    if [[ -f "$BURNIN_DMESG_MARKER_FILE" ]]; then
        previous_lines="$(cat "$BURNIN_DMESG_MARKER_FILE" 2>/dev/null || echo 0)"
    fi

    dmesg > "$tmp_file" 2>&1 || true
    current_lines="$(wc -l < "$tmp_file" | tr -d ' ')"
    if (( previous_lines < 1 )) || (( current_lines < previous_lines )); then
        cp "$tmp_file" "$BURNIN_DMESG_DELTA_FILE"
    else
        sed -n "$((previous_lines + 1)),\$p" "$tmp_file" > "$BURNIN_DMESG_DELTA_FILE"
    fi
    printf '%s\n' "$current_lines" > "$BURNIN_DMESG_MARKER_FILE"
    rm -f "$tmp_file"

    return 0
}

can_apply_cpu_affinity() {
    local cpu_list="$1"

    [[ -n "$RESOLVED_TASKSET_BIN" ]] || return 1
    [[ -n "$cpu_list" ]] || return 1

    "$RESOLVED_TASKSET_BIN" -c "$cpu_list" sh -c ':' > /dev/null 2>&1
}

calculate_ddr_memtester_size_mb() {
    local mem_total_kb=""
    local mem_available_kb=""
    local mem_total_mb=0
    local mem_available_mb=0
    local reserve_mb=0
    local size_by_total_mb=0
    local size_by_available_mb=0
    local size_mb=0

    mem_total_kb="${DDR_MEM_TOTAL_KB_OVERRIDE:-$(awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo)}"
    mem_available_kb="${DDR_MEM_AVAILABLE_KB_OVERRIDE:-$(awk '$1 == "MemAvailable:" { print $2 }' /proc/meminfo)}"
    if [[ ! "$mem_total_kb" =~ ^[0-9]+$ ]] || [[ ! "$mem_available_kb" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    mem_total_mb=$((mem_total_kb / 1024))
    mem_available_mb=$((mem_available_kb / 1024))
    reserve_mb=$((mem_total_mb * DDR_RESERVE_PERCENT / 100))
    if (( reserve_mb < DDR_RESERVE_MIN_MB )); then
        reserve_mb=$DDR_RESERVE_MIN_MB
    fi
    if (( reserve_mb > DDR_RESERVE_MAX_MB )); then
        reserve_mb=$DDR_RESERVE_MAX_MB
    fi
    size_by_total_mb=$((mem_total_mb * DDR_TEST_MAX_PERCENT / 100))
    size_by_available_mb=$((mem_available_mb - reserve_mb))

    if (( size_by_available_mb < size_by_total_mb )); then
        size_mb=$size_by_available_mb
    else
        size_mb=$size_by_total_mb
    fi

    if (( size_mb <= 0 )); then
        return 1
    fi
    if (( size_mb >= 64 )); then
        size_mb=$((size_mb / 32 * 32))
    fi
    if (( size_mb < DDR_MIN_TEST_MB )); then
        return 1
    fi

    printf '%s\n' "$size_mb"
}

get_emmc_available_mb() {
    local available_mb=0
    local work_dir=""

    if [[ -n "${EMMC_AVAILABLE_MB_OVERRIDE:-}" ]]; then
        available_mb="$EMMC_AVAILABLE_MB_OVERRIDE"
    else
        work_dir="${EMMC_WORK_DIR:-${BURNIN_RUN_DIR:-$LOG_DIR}}"
        mkdir -p "$work_dir"
        available_mb="$(df -Pk "$work_dir" | awk 'NR==2 { print int($4 / 1024) }')"
    fi
    if [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    printf '%s\n' "$available_mb"
}

get_emmc_capacity_mb() {
    local capacity_mb=0
    local size_path=""
    local sector_count=""
    local block_name=""

    if [[ -n "${EMMC_CAPACITY_MB_OVERRIDE:-}" ]]; then
        capacity_mb="$EMMC_CAPACITY_MB_OVERRIDE"
        if [[ "$capacity_mb" =~ ^[0-9]+$ ]] && (( capacity_mb > 0 )); then
            printf '%s\n' "$capacity_mb"
            return 0
        fi
        return 1
    fi

    block_name="${EMMC_BLOCK_DEVICE##*/}"
    size_path="/sys/class/block/$block_name/size"
    if [[ ! -r "$size_path" ]]; then
        return 1
    fi

    sector_count="$(tr -d '[:space:]' < "$size_path")"
    if [[ ! "$sector_count" =~ ^[0-9]+$ ]] || (( sector_count <= 0 )); then
        return 1
    fi

    capacity_mb=$((sector_count / 2048))
    if (( capacity_mb <= 0 )); then
        return 1
    fi

    printf '%s\n' "$capacity_mb"
}

calculate_emmc_test_size_mb() {
    local available_mb=0
    local capacity_mb=0
    local usable_mb=0
    local copy_dir_count=0
    local size_mb=0
    local size_by_space_mb=0
    local size_by_capacity_mb=0

    available_mb="$(get_emmc_available_mb)" || return 1
    capacity_mb="$(get_emmc_capacity_mb)" || return 1

    copy_dir_count="$EMMC_COPY_DIR_COUNT"
    if [[ ! "$copy_dir_count" =~ ^[0-9]+$ ]] || (( copy_dir_count < 1 )); then
        return 1
    fi

    usable_mb=$((available_mb - EMMC_MIN_FREE_MB))
    if (( usable_mb <= 0 )); then
        return 1
    fi

    size_by_space_mb=$((usable_mb / (copy_dir_count + 1)))
    size_by_capacity_mb=$((capacity_mb * EMMC_DATASET_SIZE_PER_GB_MB / 1024))
    if (( size_by_capacity_mb > EMMC_TARGET_SIZE_MB )); then
        size_by_capacity_mb=$EMMC_TARGET_SIZE_MB
    fi
    if (( size_by_capacity_mb < EMMC_MIN_TEST_SIZE_MB )); then
        size_by_capacity_mb=$EMMC_MIN_TEST_SIZE_MB
    fi

    if (( size_by_capacity_mb < size_by_space_mb )); then
        size_mb=$size_by_capacity_mb
    else
        size_mb=$size_by_space_mb
    fi
    if (( size_mb >= 32 )); then
        size_mb=$((size_mb / 32 * 32))
    fi
    if (( size_mb < EMMC_MIN_TEST_SIZE_MB )); then
        return 1
    fi

    printf '%s\n' "$size_mb"
}

calculate_emmc_target_write_mb() {
    local capacity_mb="$1"
    local target_write_mb=0
    local min_target_write_mb=0
    local max_target_write_mb=0

    if [[ ! "$capacity_mb" =~ ^[0-9]+$ ]] || (( capacity_mb <= 0 )); then
        return 1
    fi

    target_write_mb=$((capacity_mb * EMMC_TARGET_WRITE_PERCENT / 100))
    min_target_write_mb=$((EMMC_TARGET_WRITE_MIN_GB * 1024))
    max_target_write_mb=$((EMMC_TARGET_WRITE_MAX_GB * 1024))

    if (( target_write_mb < min_target_write_mb )); then
        target_write_mb=$min_target_write_mb
    fi
    if (( target_write_mb > max_target_write_mb )); then
        target_write_mb=$max_target_write_mb
    fi
    if (( target_write_mb > capacity_mb )); then
        target_write_mb=$capacity_mb
    fi
    if (( target_write_mb <= 0 )); then
        return 1
    fi

    printf '%s\n' "$target_write_mb"
}

calculate_emmc_max_cycles() {
    local size_mb="$1"
    local copy_dir_count="$2"
    local target_write_mb="$3"
    local per_cycle_write_mb=0
    local cycle_count=0
    local configured_max_cycles="${EMMC_MAX_CYCLES:-}"

    if [[ -n "$configured_max_cycles" ]]; then
        if [[ ! "$configured_max_cycles" =~ ^[0-9]+$ ]] || (( configured_max_cycles < 1 )); then
            return 1
        fi
        printf '%s\n' "$configured_max_cycles"
        return 0
    fi

    if [[ ! "$size_mb" =~ ^[0-9]+$ ]] || (( size_mb < 1 )); then
        return 1
    fi
    if [[ ! "$copy_dir_count" =~ ^[0-9]+$ ]] || (( copy_dir_count < 1 )); then
        return 1
    fi
    if [[ ! "$target_write_mb" =~ ^[0-9]+$ ]] || (( target_write_mb < 1 )); then
        return 1
    fi

    per_cycle_write_mb=$((size_mb * copy_dir_count))
    if (( per_cycle_write_mb <= 0 )); then
        return 1
    fi

    cycle_count=$((target_write_mb / per_cycle_write_mb))
    if (( cycle_count < 1 )); then
        cycle_count=1
    fi

    printf '%s\n' "$cycle_count"
}

drop_linux_page_cache() {
    sync
    if [[ -w /proc/sys/vm/drop_caches ]]; then
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
}

random_between() {
    local min_value="$1"
    local max_value="$2"

    if (( max_value <= min_value )); then
        printf '%s\n' "$min_value"
        return 0
    fi

    printf '%s\n' $((RANDOM % (max_value - min_value + 1) + min_value))
}

build_emmc_source_dataset() {
    local total_mb="$1"
    local dataset_dir="$2"
    local manifest_file="$3"
    local remaining_kb=0
    local chunk_kb=0
    local file_index=0
    local tmp_output=""
    local tmp_manifest="${manifest_file}.tmp"
    local rc=0

    rm -rf "$dataset_dir" "$manifest_file" "$tmp_manifest"
    mkdir -p "$dataset_dir"
    remaining_kb=$((total_mb * 1024))
    while (( remaining_kb > 0 )); do
        if (( remaining_kb <= EMMC_FILE_MIN_KB )); then
            chunk_kb="$remaining_kb"
        else
            chunk_kb="$(random_between "$EMMC_FILE_MIN_KB" "$EMMC_FILE_MAX_KB")"
            if (( chunk_kb > remaining_kb )); then
                chunk_kb="$remaining_kb"
            fi
        fi

        tmp_output="$BURNIN_RUN_DIR/emmc.dataset.$$.${file_index}.tmp"
        if "$RESOLVED_DD_BIN" if=/dev/urandom of="$dataset_dir/block.$(printf '%03d' "$file_index").bin" bs=1024 count="$chunk_kb" conv=fdatasync > "$tmp_output" 2>&1; then
            rc=0
        else
            rc=$?
        fi
        append_command_output "$tmp_output" "$EMMC_LOG_FILE" "$rc"
        rm -f "$tmp_output"
        if (( rc != 0 )); then
            rm -rf "$dataset_dir" "$manifest_file" "$tmp_manifest"
            return 1
        fi

        remaining_kb=$((remaining_kb - chunk_kb))
        file_index=$((file_index + 1))
    done

    if (cd "$dataset_dir" && "$RESOLVED_MD5SUM_BIN" ./* | sort > "$tmp_manifest"); then
        mv "$tmp_manifest" "$manifest_file"
        return 0
    fi

    rm -rf "$dataset_dir" "$manifest_file" "$tmp_manifest"
    return 1
}

write_emmc_md5_manifest() {
    local data_dir="$1"
    local manifest_file="$2"
    local tmp_manifest="${manifest_file}.tmp"

    rm -f "$manifest_file" "$tmp_manifest"
    if (cd "$data_dir" && "$RESOLVED_MD5SUM_BIN" ./* | sort > "$tmp_manifest"); then
        mv "$tmp_manifest" "$manifest_file"
        return 0
    fi

    rm -f "$manifest_file" "$tmp_manifest"
    return 1
}

run_ddr_memtester_loop() {
    local size_mb=0
    local iteration=0
    local tmp_output=""
    local rc=0
    local line=""
    local failure_markers='(^|[^[:alpha:]])FAILURE([^[:alpha:]]|$)|(^|[^[:alpha:]])failed([^[:alpha:]]|$)|Segmentation fault'

    trap 'write_status_file "$DDR_STATUS_FILE" "FAIL" "DDR burn-in terminated unexpectedly" ITERATIONS "$iteration"; exit 1' TERM INT

    size_mb="$(calculate_ddr_memtester_size_mb)" || {
        write_status_file "$DDR_STATUS_FILE" "FAIL" "Unable to calculate DDR memtester size"
        return 1
    }

    : > "$DDR_LOG_FILE"
    write_status_file "$DDR_STATUS_FILE" "RUNNING" "DDR burn-in running" SIZE_MB "$size_mb"
    printf '[%s] Starting DDR memtester size=%sM\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$size_mb" >> "$DDR_LOG_FILE"

    while true; do
        iteration=$((iteration + 1))
        tmp_output="$BURNIN_RUN_DIR/ddr.$$.${iteration}.tmp"
        printf '[%s] Iteration %s start\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$iteration" >> "$DDR_LOG_FILE"

        if "$RESOLVED_MEMTESTER_BIN" "${size_mb}M" 1 > "$tmp_output" 2>&1; then
            rc=0
        else
            rc=$?
        fi

        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$DDR_LOG_FILE"
        done < "$tmp_output"

        if grep -Eiq "$failure_markers" "$tmp_output"; then
            rm -f "$tmp_output"
            write_status_file "$DDR_STATUS_FILE" "FAIL" "memtester failure markers detected" ITERATIONS "$iteration" SIZE_MB "$size_mb"
            return 2
        fi

        rm -f "$tmp_output"
        if (( rc != 0 )); then
            write_status_file "$DDR_STATUS_FILE" "FAIL" "memtester exited with rc=${rc}" ITERATIONS "$iteration" SIZE_MB "$size_mb"
            return 3
        fi

        printf '[%s] Iteration %s pass\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$iteration" >> "$DDR_LOG_FILE"
        log_sync
    done
}

run_emmc_reliability_loop() {
    local size_mb=0
    local capacity_mb=0
    local target_write_mb=0
    local per_cycle_write_mb=0
    local cycle_count=0
    local max_cycles=0
    local copy_dir_count=0
    local dir_index=0
    local verify_dir=""
    local verify_manifest=""
    local copy_output=""
    local diff_output=""
    local rc=0

    trap 'rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"; rm -f "$EMMC_SOURCE_MD5_FILE"; write_status_file "$EMMC_STATUS_FILE" "FAIL" "eMMC burn-in terminated unexpectedly" CYCLES "$cycle_count"; exit 1' TERM INT

    size_mb="$(calculate_emmc_test_size_mb)" || {
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Insufficient free space for eMMC burn-in"
        return 1
    }
    capacity_mb="$(get_emmc_capacity_mb)" || {
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Unable to determine eMMC capacity"
        return 1
    }
    copy_dir_count="$EMMC_COPY_DIR_COUNT"
    if [[ ! "$copy_dir_count" =~ ^[0-9]+$ ]] || (( copy_dir_count < 1 )); then
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Invalid eMMC copy dir count: $EMMC_COPY_DIR_COUNT"
        return 2
    fi
    target_write_mb="$(calculate_emmc_target_write_mb "$capacity_mb")" || {
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Invalid eMMC target write budget"
        return 2
    }
    max_cycles="$(calculate_emmc_max_cycles "$size_mb" "$copy_dir_count" "$target_write_mb")" || {
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Invalid eMMC max cycles: ${EMMC_MAX_CYCLES:-dynamic}"
        return 2
    }
    per_cycle_write_mb=$((size_mb * copy_dir_count))

    rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
    rm -f "$EMMC_SOURCE_MD5_FILE"
    mkdir -p "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
    : > "$EMMC_LOG_FILE"
    write_status_file "$EMMC_STATUS_FILE" "RUNNING" "eMMC burn-in running" SIZE_MB "$size_mb" COPY_DIRS "$copy_dir_count" MAX_CYCLES "$max_cycles" CAPACITY_MB "$capacity_mb" TARGET_WRITE_MB "$target_write_mb" PER_CYCLE_WRITE_MB "$per_cycle_write_mb"
    printf '[%s] Starting eMMC burn-in source_dataset=%sMiB copy_dirs=%s max_cycles=%s target_write=%sMiB per_cycle_write=%sMiB capacity=%sMiB file_range=%s-%sKiB\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$size_mb" \
        "$copy_dir_count" \
        "$max_cycles" \
        "$target_write_mb" \
        "$per_cycle_write_mb" \
        "$capacity_mb" \
        "$EMMC_FILE_MIN_KB" \
        "$EMMC_FILE_MAX_KB" >> "$EMMC_LOG_FILE"

    if ! build_emmc_source_dataset "$size_mb" "$EMMC_SOURCE_DIR" "$EMMC_SOURCE_MD5_FILE"; then
        rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
        rm -f "$EMMC_SOURCE_MD5_FILE"
        write_status_file "$EMMC_STATUS_FILE" "FAIL" "Failed to build source dataset" CYCLES "$cycle_count" SIZE_MB "$size_mb"
        return 3
    fi

    while true; do
        cycle_count=$((cycle_count + 1))
        printf '[%s] Cycle %s start source_dataset=%sMiB copy_dirs=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$cycle_count" \
            "$size_mb" \
            "$copy_dir_count" >> "$EMMC_LOG_FILE"

        for ((dir_index = 0; dir_index < copy_dir_count; dir_index++)); do
            verify_dir="$EMMC_VERIFY_ROOT_DIR/$dir_index"
            copy_output="$BURNIN_RUN_DIR/emmc.copy.$$.${cycle_count}.${dir_index}.tmp"
            rm -rf "$verify_dir"
            if cp -rf "$EMMC_SOURCE_DIR" "$verify_dir" > "$copy_output" 2>&1; then
                rc=0
            else
                rc=$?
            fi
            append_command_output "$copy_output" "$EMMC_LOG_FILE" "$rc"
            rm -f "$copy_output"
            if (( rc != 0 )); then
                rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
                rm -f "$EMMC_SOURCE_MD5_FILE"
                write_status_file "$EMMC_STATUS_FILE" "FAIL" "eMMC dataset copy failed rc=${rc}" CYCLES "$cycle_count" DIR_INDEX "$dir_index" SIZE_MB "$size_mb"
                return 4
            fi
        done

        drop_linux_page_cache
        sleep "$EMMC_CACHE_DROP_SLEEP_SEC"
        drop_linux_page_cache
        sleep "$EMMC_CACHE_DROP_SLEEP_SEC"

        for ((dir_index = 0; dir_index < copy_dir_count; dir_index++)); do
            verify_dir="$EMMC_VERIFY_ROOT_DIR/$dir_index"
            verify_manifest="$EMMC_VERIFY_MD5_DIR/dest${dir_index}.md5"
            diff_output="$BURNIN_RUN_DIR/emmc.diff.$$.${cycle_count}.${dir_index}.tmp"

            if ! write_emmc_md5_manifest "$verify_dir" "$verify_manifest"; then
                rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
                rm -f "$EMMC_SOURCE_MD5_FILE" "$diff_output"
                write_status_file "$EMMC_STATUS_FILE" "FAIL" "Failed to generate verify md5 manifest" CYCLES "$cycle_count" DIR_INDEX "$dir_index" SIZE_MB "$size_mb"
                return 5
            fi

            if diff -u "$EMMC_SOURCE_MD5_FILE" "$verify_manifest" > "$diff_output" 2>&1; then
                rc=0
            else
                rc=$?
            fi
            append_command_output "$diff_output" "$EMMC_LOG_FILE" "$rc"
            rm -f "$diff_output" "$verify_manifest"
            if (( rc != 0 )); then
                rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
                rm -f "$EMMC_SOURCE_MD5_FILE"
                write_status_file "$EMMC_STATUS_FILE" "FAIL" "eMMC md5 manifest mismatch" CYCLES "$cycle_count" DIR_INDEX "$dir_index" SIZE_MB "$size_mb"
                return 6
            fi

            rm -rf "$verify_dir"
        done

        printf '[%s] Cycle %s pass source_dataset=%sMiB copy_dirs=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$cycle_count" \
            "$size_mb" \
            "$copy_dir_count" >> "$EMMC_LOG_FILE"

        if (( max_cycles > 0 && cycle_count >= max_cycles )); then
            printf '[%s] eMMC cycle limit reached cycles=%s, stopping eMMC stress\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$cycle_count" >> "$EMMC_LOG_FILE"
            rm -rf "$EMMC_SOURCE_DIR" "$EMMC_VERIFY_ROOT_DIR" "$EMMC_VERIFY_MD5_DIR"
            rm -f "$EMMC_SOURCE_MD5_FILE"
            write_status_file "$EMMC_STATUS_FILE" "COMPLETED" "Reached configured cycle limit" CYCLES "$cycle_count" SIZE_MB "$size_mb" COPY_DIRS "$copy_dir_count" CAPACITY_MB "$capacity_mb" TARGET_WRITE_MB "$target_write_mb" PER_CYCLE_WRITE_MB "$per_cycle_write_mb"
            return 0
        fi

        log_sync
    done
}

ensure_burnin_binaries() {
    RESOLVED_STRESS_NG_BIN="$(resolve_required_binary "$STRESS_NG_BIN" || true)"
    RESOLVED_MEMTESTER_BIN="$(resolve_required_binary "$MEMTESTER_BIN" || true)"
    RESOLVED_GLMARK2_BIN="$(resolve_required_binary "$GLMARK2_BIN" || true)"
    RESOLVED_DD_BIN="$(resolve_required_binary "$DD_BIN" || true)"
    RESOLVED_MD5SUM_BIN="$(resolve_required_binary "$MD5SUM_BIN" || true)"
    RESOLVED_TASKSET_BIN="$(resolve_required_binary "$TASKSET_BIN" || true)"

    [[ -n "$RESOLVED_STRESS_NG_BIN" ]] || {
        xlog "ERROR" "Missing required binary: $STRESS_NG_BIN"
        return 1
    }
    [[ -n "$RESOLVED_MEMTESTER_BIN" ]] || {
        xlog "ERROR" "Missing required binary: $MEMTESTER_BIN"
        return 1
    }
    [[ -n "$RESOLVED_GLMARK2_BIN" ]] || {
        xlog "ERROR" "Missing required binary: $GLMARK2_BIN"
        return 1
    }
    [[ -n "$RESOLVED_DD_BIN" ]] || {
        xlog "ERROR" "Missing required binary: $DD_BIN"
        return 1
    }
    [[ -n "$RESOLVED_MD5SUM_BIN" ]] || {
        xlog "ERROR" "Missing required binary: $MD5SUM_BIN"
        return 1
    }

    return 0
}

finalize_burnin() {
    local status="$1"
    local reason="$2"

    write_status_file "$BURNIN_STATUS_FILE" "$status" "$reason" BOARD_VARIANT "$BOARD_VARIANT"
    if [[ "$status" == "FAIL" ]]; then
        set_status_led_default_on
        fan_power_set 1
    fi
    xlog "INFO" "Burn-in finished with status=$status reason=$reason"
}

run_burn_in_watchdog() {
    local start_epoch="$1"
    local cpu_pid="$2"
    local gpu_pid="$3"
    local ddr_pid="$4"
    local emmc_pid="$5"
    local elapsed_s=0
    local dmesg_error_count=0
    local failure_reason=""
    local now=0
    local soc_mc=0
    local big0_mc=0
    local big1_mc=0
    local gpu_mc=0
    local emmc_status=""
    local emmc_reason=""

    trap 'write_status_file "$WATCHDOG_STATUS_FILE" "FAIL" "Watchdog terminated unexpectedly"; exit 1' TERM INT

    write_status_file "$WATCHDOG_STATUS_FILE" "RUNNING" "Watchdog monitoring active"
    while true; do
        now="$(date +%s)"
        elapsed_s=$((now - start_epoch))
        dmesg_error_count=0
        scan_new_dmesg_errors || true
        record_monitor_sample "burnin" "$elapsed_s" "$dmesg_error_count"

        soc_mc="$(read_thermal_temp_mc "soc-thermal")"
        big0_mc="$(read_thermal_temp_mc "bigcore0-thermal")"
        big1_mc="$(read_thermal_temp_mc "bigcore1-thermal")"
        gpu_mc="$(read_thermal_temp_mc "gpu-thermal")"

        if (( soc_mc >= WARN_TEMP_MC )); then xlog "WARN" "soc-thermal warning temperature $(format_temp_c "$soc_mc")C"; fi
        if (( big0_mc >= WARN_TEMP_MC )); then xlog "WARN" "bigcore0-thermal warning temperature $(format_temp_c "$big0_mc")C"; fi
        if (( big1_mc >= WARN_TEMP_MC )); then xlog "WARN" "bigcore1-thermal warning temperature $(format_temp_c "$big1_mc")C"; fi
        if (( gpu_mc >= WARN_TEMP_MC )); then xlog "WARN" "gpu-thermal warning temperature $(format_temp_c "$gpu_mc")C"; fi

        if [[ -z "$failure_reason" ]] && ! kill -0 "$cpu_pid" 2>/dev/null; then
            failure_reason="CPU workload exited unexpectedly"
        fi
        if [[ -z "$failure_reason" ]] && ! kill -0 "$gpu_pid" 2>/dev/null; then
            failure_reason="GPU workload exited unexpectedly"
        fi
        if [[ -z "$failure_reason" ]] && ! kill -0 "$ddr_pid" 2>/dev/null; then
            failure_reason="DDR workload exited unexpectedly"
        fi
        if [[ -z "$failure_reason" ]] && ! kill -0 "$emmc_pid" 2>/dev/null; then
            load_status_file "$EMMC_STATUS_FILE"
            emmc_status="${STATUS:-}"
            emmc_reason="${REASON:-}"
            if [[ "$emmc_status" != "COMPLETED" ]]; then
                failure_reason="eMMC workload exited unexpectedly"
            elif [[ -n "$emmc_reason" ]]; then
                xlog "INFO" "eMMC workload completed: $emmc_reason"
            else
                xlog "INFO" "eMMC workload completed"
            fi
        fi

        if [[ -n "$failure_reason" ]]; then
            write_status_file "$WATCHDOG_STATUS_FILE" "FAIL" "$failure_reason"
            return 1
        fi

        sleep "$MONITOR_INTERVAL_SEC"
    done
}

run_burn_in_test() {
    local start_epoch=0
    local led_blink_pid=0
    local aging_led_pid=0
    local fan_ctrl_pid=0
    local cpu_pid=0
    local gpu_pid=0
    local ddr_pid=0
    local emmc_pid=0
    local watchdog_pid=0
    local watchdog_rc=0
    local watchdog_status=""
    local watchdog_reason=""
    local ddr_status=""
    local ddr_reason=""
    local emmc_status=""
    local emmc_reason=""
    local gpu_cmd=()
    local cpu_load_percent=0

    xlog "INFO" "Entering burn-in test mode"
    setup_burnin_paths
    aging_fan_on
    record_monitor_header
    init_dmesg_marker

    if ! ensure_burnin_binaries; then
        finalize_burnin "FAIL" "Missing required burn-in binary"
        return 200
    fi

    write_status_file "$BURNIN_STATUS_FILE" "RUNNING" "Burn-in workloads starting" BOARD_VARIANT "$BOARD_VARIANT"
    : > "$CPU_LOG_FILE"
    : > "$GPU_LOG_FILE"

    trap 'touch "$BURNIN_STOP_FLAG"' TERM INT
    start_epoch="$(date +%s)"
    cpu_load_percent="$BURNIN_CPU_LOAD_PERCENT"
    if [[ ! "$cpu_load_percent" =~ ^[0-9]+$ ]] || (( cpu_load_percent < 1 || cpu_load_percent > 100 )); then
        finalize_burnin "FAIL" "Invalid CPU load percent: $BURNIN_CPU_LOAD_PERCENT"
        return 205
    fi

    run_status_led_blink_loop > /dev/null 2>&1 &
    led_blink_pid=$!
    xlog "INFO" "Launched status LED blink loop (pid $led_blink_pid)"

    run_aging_led_heartbeat > /dev/null &
    aging_led_pid=$!
    xlog "INFO" "Launched aging LED heartbeat (pid $aging_led_pid)"

    run_fan_control_loop > /dev/null &
    fan_ctrl_pid=$!
    xlog "INFO" "Launched fan control loop (pid $fan_ctrl_pid)"

    "$RESOLVED_STRESS_NG_BIN" --cpu 0 --cpu-method matrixprod --verify --cpu-load "$cpu_load_percent" --timeout "$BURNIN_CPU_TIMEOUT" > "$CPU_LOG_FILE" 2>&1 &
    cpu_pid=$!
    xlog "INFO" "Launched CPU burn-in (pid $cpu_pid)"

    gpu_cmd=("$RESOLVED_GLMARK2_BIN" --off-screen --run-forever -b terrain)
    if can_apply_cpu_affinity "$GPU_TASKSET"; then
        gpu_cmd=("$RESOLVED_TASKSET_BIN" -c "$GPU_TASKSET" "${gpu_cmd[@]}")
    elif [[ -n "$RESOLVED_TASKSET_BIN" ]] && [[ -n "$GPU_TASKSET" ]]; then
        xlog "WARN" "Skipping GPU taskset '$GPU_TASKSET' because it is invalid on this board"
    fi
    "${gpu_cmd[@]}" > "$GPU_LOG_FILE" 2>&1 &
    gpu_pid=$!
    xlog "INFO" "Launched GPU burn-in (pid $gpu_pid)"

    run_ddr_memtester_loop > /dev/null 2>&1 &
    ddr_pid=$!
    xlog "INFO" "Launched DDR burn-in (pid $ddr_pid)"

    run_emmc_reliability_loop > /dev/null 2>&1 &
    emmc_pid=$!
    xlog "INFO" "Launched eMMC burn-in (pid $emmc_pid)"

    run_burn_in_watchdog "$start_epoch" "$cpu_pid" "$gpu_pid" "$ddr_pid" "$emmc_pid" > /dev/null 2>&1 &
    watchdog_pid=$!
    xlog "INFO" "Launched burn-in watchdog (pid $watchdog_pid)"

    while true; do
        if [[ -f "$BURNIN_STOP_FLAG" ]]; then
            xlog "WARN" "Received unexpected external termination request for burn-in"
            kill_pid_if_running "$led_blink_pid" "status LED blink"
            kill_pid_if_running "$aging_led_pid" "aging LED heartbeat"
            aging_led_set "$AGING_LED_ON_VALUE"
            kill_pid_if_running "$fan_ctrl_pid" "fan control"
            kill_pid_if_running "$watchdog_pid" "burn-in watchdog"
            if wait "$watchdog_pid"; then :; else :; fi
            kill_pid_if_running "$cpu_pid" "CPU burn-in"
            kill_pid_if_running "$gpu_pid" "GPU burn-in"
            kill_pid_if_running "$ddr_pid" "DDR burn-in"
            kill_pid_if_running "$emmc_pid" "eMMC burn-in"
            if wait "$ddr_pid"; then :; else :; fi
            if wait "$emmc_pid"; then :; else :; fi
            ensure_status_terminal "$DDR_STATUS_FILE" "FAIL" "DDR burn-in terminated by supervisor"
            ensure_status_terminal "$EMMC_STATUS_FILE" "FAIL" "eMMC burn-in terminated by supervisor"
            finalize_burnin "FAIL" "Burn-in terminated unexpectedly"
            trap - TERM INT
            rm -f "$BURNIN_STOP_FLAG"
            return 206
        fi

        if ! kill -0 "$watchdog_pid" 2>/dev/null; then
            break
        fi

        sleep "$SUPERVISOR_POLL_INTERVAL_SEC"
    done

    if wait "$watchdog_pid"; then
        watchdog_rc=0
    else
        watchdog_rc=$?
    fi

    load_status_file "$WATCHDOG_STATUS_FILE"
    watchdog_status="${STATUS:-}"
    watchdog_reason="${REASON:-}"

    kill_pid_if_running "$led_blink_pid" "status LED blink"
    kill_pid_if_running "$aging_led_pid" "aging LED heartbeat"
    aging_led_set "$AGING_LED_ON_VALUE"
    kill_pid_if_running "$fan_ctrl_pid" "fan control"
    kill_pid_if_running "$cpu_pid" "CPU burn-in"
    kill_pid_if_running "$gpu_pid" "GPU burn-in"
    kill_pid_if_running "$ddr_pid" "DDR burn-in"
    kill_pid_if_running "$emmc_pid" "eMMC burn-in"
    if wait "$ddr_pid"; then :; else :; fi
    if wait "$emmc_pid"; then :; else :; fi
    ensure_status_terminal "$DDR_STATUS_FILE" "FAIL" "DDR burn-in terminated by supervisor"
    ensure_status_terminal "$EMMC_STATUS_FILE" "FAIL" "eMMC burn-in terminated by supervisor"

    load_status_file "$DDR_STATUS_FILE"
    ddr_status="${STATUS:-}"
    ddr_reason="${REASON:-}"
    load_status_file "$EMMC_STATUS_FILE"
    emmc_status="${STATUS:-}"
    emmc_reason="${REASON:-}"

    trap - TERM INT
    rm -f "$BURNIN_STOP_FLAG"

    if [[ "$watchdog_status" == "FAIL" ]] || (( watchdog_rc != 0 )); then
        if [[ -z "$watchdog_reason" ]]; then
            watchdog_reason="Burn-in watchdog exited unexpectedly"
        fi
        finalize_burnin "FAIL" "$watchdog_reason"
        return 201
    fi

    if [[ "$ddr_status" == "FAIL" ]]; then
        finalize_burnin "FAIL" "$ddr_reason"
        return 202
    fi

    if [[ "$emmc_status" == "FAIL" ]]; then
        finalize_burnin "FAIL" "$emmc_reason"
        return 203
    fi

    finalize_burnin "FAIL" "Burn-in watchdog exited without a terminal state"
    return 204
}

gpio_export() {
    [ -d "/sys/class/gpio/gpio$1" ] || echo "$1" > /sys/class/gpio/export 2>/dev/null || true
    sleep 0.05
}

gpio_dir() {
    echo "$2" > "/sys/class/gpio/gpio$1/direction" 2>/dev/null || true
}

gpio_set() {
    echo "$2" > "/sys/class/gpio/gpio$1/value" 2>/dev/null || true
}

gpio_get() {
    cat "/sys/class/gpio/gpio$1/value" 2>/dev/null || true
}

gpio_unexport() {
    echo "$1" > /sys/class/gpio/unexport 2>/dev/null || true
}

aging_board_present() {
    local value=""

    gpio_export "$AGING_MODE_GPIO"
    gpio_dir "$AGING_MODE_GPIO" in
    sleep 0.05
    value="$(gpio_get "$AGING_MODE_GPIO")"
    gpio_unexport "$AGING_MODE_GPIO"
    xlog "INFO" "MODE_SWITCH(GPIO4_A1/129)=$value"
    [ "$value" = "0" ]
}

fan_power_set() {
    gpio_set "$FAN_PWR_GPIO" "$1"
}

run_fan_control_loop() {
    local max_t=0 t zone fan_on=1 state=on

    while true; do
        max_t=0
        for zone in soc-thermal bigcore0-thermal bigcore1-thermal gpu-thermal; do
            t="$(read_thermal_temp_mc "$zone")"
            (( t > max_t )) && max_t="$t"
        done
        if (( max_t > FAN_PWR_TARGET_HIGH )); then
            if (( fan_on == 0 )); then
                fan_power_set 1
                fan_on=1
            fi
        elif (( max_t < FAN_PWR_TARGET_LOW )); then
            if (( fan_on == 1 )); then
                fan_power_set 0
                fan_on=0
            fi
        fi
        state=off
        (( fan_on == 1 )) && state=on
        xlog "INFO" "fan pwr=${state} max_temp=$(format_temp_c "$max_t")"
        sleep "$FAN_PWR_CONTROL_INTERVAL"
    done
}

aging_fan_on() {
    gpio_export "$FAN_PWR_GPIO"
    gpio_dir "$FAN_PWR_GPIO" out
    gpio_set "$FAN_PWR_GPIO" 1
    xlog "INFO" "Aging fan on: FAN_PWR(${FAN_PWR_GPIO})=1 model=${SOM_MODEL:-unknown}"
}

aging_led_hwmon() {
    local h
    for h in $AGING_LED_HWMON_GLOB; do
        [ -w "$h/pwm1" ] || continue
        printf '%s\n' "$h"
        return 0
    done
    return 1
}

aging_led_set() {
    local h
    h="$(aging_led_hwmon)" || return 1
    echo "$1" > "$h/pwm1" 2>/dev/null
}

run_aging_led_heartbeat() {
    local h
    h="$(aging_led_hwmon)" || {
        xlog "WARN" "pwm-fan pwm1 not found; LED3 heartbeat disabled"
        return 1
    }
    xlog "INFO" "LED3 heartbeat on $h/pwm1 on=$AGING_LED_ON_VALUE off=$AGING_LED_OFF_VALUE"
    while true; do
        echo "$AGING_LED_ON_VALUE" > "$h/pwm1" 2>/dev/null
        sleep 0.5
        echo "$AGING_LED_OFF_VALUE" > "$h/pwm1" 2>/dev/null
        sleep 0.5
    done
}


main() {
    local start_rc=0
    local file_name=""

    if ! assert_expected_board; then
        return 101
    fi

    if [[ "$ENABLE_CPU_MAX_FREQ" == "1" ]]; then
        set_all_cpu_max_freq
    fi

    if ! wait_for_usb_block_device; then
        if aging_board_present; then
            xlog "INFO" "Aging backplane detected, entering burn-in test"
            if run_burn_in_test; then
                return 0
            fi
            return $?
        fi
        xlog "ERROR" "No USB block device after ${CONFIG_MEDIA_PRESENCE_WAIT_SEC}s." \
            "The config stick is fitted before power-on, so it should always" \
            "enumerate: check the stick, the fixture USB port and the cable."
        return 11
    fi

    xlog "INFO" "==> Config media detection"
    if ! CONFIG_DIR="$(wait_for_config_dir)"; then
        xlog "ERROR" "Config media detection failed, aborting"
        return 10
    fi
    xlog "INFO" "Using config directory $CONFIG_DIR" \
        "(device: $(findmnt -n -o SOURCE --target "$CONFIG_DIR" 2>/dev/null || echo unknown))"

    for file_name in $CONFIG_FILES; do
        if [[ ! -f "$CONFIG_DIR/$file_name" ]]; then
            xlog "ERROR" "File $file_name not found in $CONFIG_DIR, aborting"
            return 20
        fi
        if [[ ! -r "$CONFIG_DIR/$file_name" ]]; then
            xlog "ERROR" "File $file_name exists but is not readable, aborting"
            return 21
        fi
    done

    mkdir -p "$TOOL_DIR" || {
        xlog "ERROR" "Failed to create tool dir $TOOL_DIR"
        return 22
    }

    for file_name in configs.json product_configs.json; do
        cp -f "$CONFIG_DIR/$file_name" "$TOOL_DIR/" || {
            xlog "ERROR" "Failed to copy $file_name to $TOOL_DIR"
            return 23
        }
    done

    cp -f "$CONFIG_DIR/start.sh" "$TOOL_DIR/start.sh" || {
        xlog "ERROR" "Failed to copy start.sh to $TOOL_DIR"
        return 24
    }
    chmod +x "$TOOL_DIR/start.sh" || {
        xlog "ERROR" "Failed to chmod start.sh"
        return 25
    }

    xlog "INFO" "All required files copied, executing start.sh"
    start_rc=0
    "$TOOL_DIR/start.sh" || start_rc=$?
    if (( start_rc != 0 )); then
        xlog "ERROR" "start.sh exited with code $start_rc"
        return "$start_rc"
    fi

    xlog "INFO" "start.sh executed successfully"
    return 0
}

if [[ "${PRODUCTION_DEPLOY_SOURCE_ONLY:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

main "$@"
