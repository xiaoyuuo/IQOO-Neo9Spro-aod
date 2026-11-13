#!/system/bin/sh
# 开机最早阶段：写属性 + 挂载（可按 config.ini 的 DISABLE=1 跳过）
MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
if [ ! -f "$CONF" ] && [ -f "$MODDIR/config.ini" ]; then
    cp "$MODDIR/config.ini" "$CONF" 2>/dev/null
fi

fa_conf_sync
fa_backup_settings
fa_log "==== boot: post-fs-data (v3.1) ===="
fa_write_props

if [ "$(fa_conf DISABLE 0)" = "1" ] || [ "$(fa_conf MOUNT_SYSFS 1)" != "1" ]; then
    fa_log "DISABLE=1, skip mount"
else
    if [ -e "$SYSFS" ]; then
        # 开机第一现场：先抓「真·原厂串 + 真标签」，再挂载
        fa_capture_boot_orig
        fa_refresh_orig
        fa_apply_sysfs
    else
        fa_log "sysfs not ready at post-fs-data, service.sh will retry"
    fi
fi
