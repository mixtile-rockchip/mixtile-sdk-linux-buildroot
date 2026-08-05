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
