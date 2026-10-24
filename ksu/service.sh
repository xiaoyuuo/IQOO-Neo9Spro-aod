#!/system/bin/sh
# 开机末尾：属性 / 面板串挂载 / 熄屏显示 APK 补丁
MODDIR=${0%/*}
. "$MODDIR/common.sh"

fa_log "==== boot: service.sh (v1.5) ===="
sleep 3
fa_write_props
fa_apply_aod_type

if [ "$(fa_conf DISABLE 0)" = "1" ] || [ "$(fa_conf MOUNT_SYSFS 1)" != "1" ]; then
    fa_log "DISABLE=1, service skip"
    exit 0
fi

# 1) 面板能力串
late=0
if ! fa_is_mounted; then
    if fa_mount_wait; then
        late=1
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
fi

if [ "$late" = "1" ]; then
    fa_log "restart systemui + nightpearl to reload"
    killall com.android.systemui 2>/dev/null
    killall com.vivo.nightpearl 2>/dev/null
fi

fa_log "service.sh done: aodinfo=$(fa_is_mounted && echo yes || echo no) np=$(fa_np_base)"
