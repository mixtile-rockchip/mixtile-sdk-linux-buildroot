#!/bin/bash

set -euo pipefail

LOG_DIR="/userdata/production_log"
LOG_FILE="$LOG_DIR/production.log"

mkdir -p "$LOG_DIR"

log_sync() {
    sync
}

exec > >(stdbuf -oL -eL tee -a "$LOG_FILE") 2>&1

xlog() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$$] [$level] $msg" >&2
    log_sync
}

STATUS_LED_TRIGGER="/sys/class/leds/sys_status_led/trigger"

set_status_led_default_on() {
    xlog "INFO" "Setting status LED to default-on"
    echo "default-on" > "$STATUS_LED_TRIGGER" 2>/dev/null || xlog "WARN" "Failed to set $STATUS_LED_TRIGGER to default-on"
}

cleanup() {
    if [ "${MOUNT_POINT:-}" ] && mountpoint -q "$MOUNT_POINT"; then
        xlog "INFO" "Unmounting $MOUNT_POINT due to error or exit"
        umount "$MOUNT_POINT" || xlog "WARN" "Failed to unmount $MOUNT_POINT during cleanup"
    fi
}
trap cleanup EXIT

mount_sdcard_partition() {
    SD_DEV="/dev/mmcblk1"
    MOUNT_POINT="/mnt/sdcard"

    if [ ! -b "$SD_DEV" ]; then
        xlog "ERROR" "SD card device $SD_DEV does not exist!"
        return 1
    fi

    PARTITION="${SD_DEV}p1"
    if [ ! -b "$PARTITION" ]; then
        xlog "ERROR" "SD card partition $PARTITION does not exist!"
        return 2
    fi

    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT" || {
            xlog "ERROR" "Failed to create mount point $MOUNT_POINT"
            return 4
        }
    fi

    if mountpoint -q "$MOUNT_POINT"; then
        xlog "INFO" "$MOUNT_POINT is already a mount point"
        mount_dev=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
        if [ "$mount_dev" = "$PARTITION" ]; then
            xlog "INFO" "$PARTITION is already mounted at $MOUNT_POINT"
            return 0
        else
            xlog "ERROR" "$MOUNT_POINT is mounted to $mount_dev, not $PARTITION"
            return 5
        fi
    fi

    mount "$PARTITION" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        xlog "ERROR" "Failed to mount $PARTITION to $MOUNT_POINT!"
        return 3
    fi

    xlog "INFO" "Successfully mounted $PARTITION to $MOUNT_POINT"
    return 0
}

check_gpio38_flip() {
    local gpio=38
    local value_old value_new
    local changed=0
    local duration=3
    local interval=0.05
    local count=$((duration * 20))

    if [ ! -d "/sys/class/gpio/gpio${gpio}" ]; then
        echo "${gpio}" > /sys/class/gpio/export 2>/dev/null
        sleep 0.05
        echo in > "/sys/class/gpio/gpio${gpio}/direction" 2>/dev/null
        xlog "INFO" "Exported and set GPIO${gpio} direction to in"
    fi

    if [ ! -e "/sys/class/gpio/gpio${gpio}/value" ]; then
        xlog "WARN" "GPIO38 not exported or unavailable, skip change detection"
        return 1
    fi

    value_old=$(cat "/sys/class/gpio/gpio${gpio}/value" 2>/dev/null)
    for ((i=0; i<$count; i++)); do
        value_new=$(cat "/sys/class/gpio/gpio${gpio}/value" 2>/dev/null)
        if [ "$value_new" != "$value_old" ]; then
            changed=1
            break
        fi
        sleep $interval
    done

    if [ $changed -eq 1 ]; then
        xlog "INFO" "GPIO38 input level changed within 3 seconds"
        return 0
    else
        xlog "INFO" "GPIO38 input level did not change within 3 seconds"
        return 1
    fi
}


run_burn_in_test() {
    xlog "INFO" "Entering burn-in test mode"
    log_sync

    stress-ng -t 0 --cpu 0 --cpu-load 100 > /dev/null 2>&1 &
    local stress_pid=$!
    xlog "INFO" "Launched stress-ng (pid $stress_pid)"
    log_sync

    glmark2-es2-drm -b terrain --run-forever --off-screen > /dev/null 2>&1 &
    local glmark_pid=$!
    xlog "INFO" "Launched glmark2-es2-drm (pid $glmark_pid)"
    log_sync

    while true; do
        sleep 2
        if ! kill -0 "$stress_pid" 2>/dev/null; then
            xlog "ERROR" "stress-ng terminated unexpectedly!"
            set_status_led_default_on
            kill -9 "$glmark_pid" 2>/dev/null || true
            log_sync
            exit 200
        fi
        if ! kill -0 "$glmark_pid" 2>/dev/null; then
            xlog "ERROR" "glmark2-es2-drm terminated unexpectedly!"
            set_status_led_default_on
            kill -9 "$stress_pid" 2>/dev/null || true
            log_sync
            exit 201
        fi
    done
}

main() {
    SD_DEV="/dev/mmcblk1"
    PARTITION="${SD_DEV}p1"
    MOUNT_POINT="/mnt/sdcard"
    TOOL_DIR="/root/ProductionTool"

    if [ ! -b "$SD_DEV" ] || [ ! -b "$PARTITION" ]; then
        xlog "WARN" "No SD card detected. Checking for GPIO38 flip for burn-in test."
        log_sync
        if check_gpio38_flip; then
            xlog "INFO" "GPIO38 level flipped within 3 seconds -- entering burn-in test."
            log_sync
            run_burn_in_test
            exit 0
        else
            xlog "WARN" "GPIO38 did not flip, not entering burn-in test. Exiting."
            log_sync
            exit 100
        fi
    fi

    xlog "INFO" "==> SD card partition detection and mount"
    log_sync
    mount_sdcard_partition
    if [ $? -ne 0 ]; then
        xlog "ERROR" "SD card partition mount failed, aborting"
        log_sync
        exit 10
    fi

    for f in configs.json product_configs.json start.sh; do
        if [ ! -f "$MOUNT_POINT/$f" ]; then
            xlog "ERROR" "File $f not found in SD card root, aborting"
            log_sync
            exit 20
        fi
        if [ ! -r "$MOUNT_POINT/$f" ]; then
            xlog "ERROR" "File $f exists but is not readable, aborting"
            log_sync
            exit 21
        fi
    done

    mkdir -p "$TOOL_DIR" || {
        xlog "ERROR" "Failed to create tool dir $TOOL_DIR"
        log_sync
        exit 22
    }

    for f in configs.json product_configs.json; do
        cp -f "$MOUNT_POINT/$f" "$TOOL_DIR/" || {
            xlog "ERROR" "Failed to copy $f to $TOOL_DIR"
            log_sync
            exit 23
        }
    done
    cp -f "$MOUNT_POINT/start.sh" "$TOOL_DIR/start.sh" || {
        xlog "ERROR" "Failed to copy start.sh to $TOOL_DIR"
        log_sync
        exit 24
    }
    chmod +x "$TOOL_DIR/start.sh" || {
        xlog "ERROR" "Failed to chmod start.sh"
        log_sync
        exit 25
    }

    umount "$MOUNT_POINT"
    if mountpoint -q "$MOUNT_POINT"; then
        xlog "ERROR" "Failed to unmount $MOUNT_POINT"
        log_sync
        exit 30
    fi
    xlog "INFO" "SD card unmounted from $MOUNT_POINT"
    log_sync

    trap - EXIT

    xlog "INFO" "All required files copied, executing start.sh"
    log_sync
    "$TOOL_DIR/start.sh"
    ret=$?
    if [ $ret -ne 0 ]; then
        xlog "ERROR" "start.sh exited with code $ret"
        log_sync
        exit $ret
    fi
    xlog "INFO" "start.sh executed successfully"
    log_sync
}

main "$@"
