#!/system/bin/sh
# 开机最早阶段：写属性 + 挂载（可按 config.ini 的 DISABLE=1 跳过）
MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
if [ ! -f "$CONF" ] && [ -f "$MODDIR/config.ini" ]; then
    cp "$MODDIR/config.ini" "$CONF" 2>/dev/null
fi

fa_conf_sync
fa_log "==== boot: post-fs-data (v1.4) ===="
fa_write_props

if [ "$(fa_conf DISABLE 0)" = "1" ] || [ "$(fa_conf MOUNT_SYSFS 1)" != "1" ]; then
    fa_log "DISABLE=1, skip mount"
else
    if [ -e "$SYSFS" ]; then
        fa_mount_fake
    else
        fa_log "sysfs not ready at post-fs-data, service.sh will retry"
    fi
fi
