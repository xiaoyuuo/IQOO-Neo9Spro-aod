#!/system/bin/sh
# 开机末尾：属性 / 面板串挂载 / 熄屏显示 APK 补丁 / 亮度守卫
MODDIR=${0%/*}
. "$MODDIR/common.sh"

fa_log "==== boot: service.sh (v3.0) ===="
sleep 3
fa_write_props
fa_apply_aod_type

if [ "$(fa_conf DISABLE 0)" = "1" ]; then
    fa_log "DISABLE=1, service skip (guard/sensor 也一并停)"
    fa_guard_stop
    fa_sensor_stop
    exit 0
fi

# 1) 面板能力串
late=0
if [ "$(fa_conf MOUNT_SYSFS 1)" = "1" ]; then
    if ! fa_is_mounted; then
        if fa_mount_wait; then
            late=1
        fi
    fi
fi

# 2) 等系统启动完，给「熄屏显示」打补丁（改它自己的白名单判断）
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
    i=$((i + 1))
    sleep 1
done
if fa_np_patched; then
    late=1
    # 挂上补丁包后再补杀一次，确保夜明珠用新 dex 重启（ART 可能先用旧 odex）
    ( sleep 3; killall com.vivo.nightpearl 2>/dev/null ) &
fi

if [ "$late" = "1" ]; then
    fa_log "restart systemui + nightpearl to reload"
    killall com.android.systemui 2>/dev/null
    killall com.vivo.nightpearl 2>/dev/null
else
    # v5.6：开机后让熄屏显示重新初始化一次，效果与点「执行」后对齐
    # （实测：开机默认的 AOD 不实时刷新，点过 Action 后才实时）
    ( sleep 3; killall com.vivo.nightpearl 2>/dev/null; fa_log "boot reinit: nightpearl restarted" ) &
fi

# 3) 亮度守卫（解锁后把亮度重新下发一次，修「卡在熄屏亮度」）
fa_backup_settings
fa_fwd_start
fa_apply_auto_bright
fa_guard_start
# 4) 传感器桥（光线/运动 + 真熄屏），再启动 AOD 超时
fa_sensor_start
fa_aod_start
fa_modewatch_start

fa_log "service.sh done: aodinfo=$(fa_is_mounted && echo yes || echo no) np=$(fa_np_base) guard=$(fa_guard_running && echo yes || echo no) aodkeep=$(fa_aod_running && echo yes || echo no) sensor=$(fa_sensor_running && echo yes || echo no)"

# v7.0：把清理脚本额外放一份到 /data/local/tmp，
# 这样即使模块被“直接删除”（没走 uninstall.sh），也能手动执行：
#   sh /data/local/tmp/aod_clean.sh
# 软重启（热重启）不会清 bind mount，执行它就能立刻恢复干净。
if [ -f "$MODDIR/uninstall.sh" ]; then
    cp -f "$MODDIR/uninstall.sh" /data/local/tmp/aod_clean.sh 2>/dev/null
    chmod 0755 /data/local/tmp/aod_clean.sh 2>/dev/null
    fa_log "cleanup script copied to /data/local/tmp/aod_clean.sh"
fi