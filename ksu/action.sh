#!/system/bin/sh
# 「执行 / Action」按钮：按 config.ini 重新应用一次 + 诊断报告
MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
if [ ! -f "$CONF" ] && [ -f "$MODDIR/config.ini" ]; then
    cp "$MODDIR/config.ini" "$CONF" 2>/dev/null
fi
fa_conf_sync

fa_log "==== action: apply (v3.7) ===="
fa_write_props
fa_apply_aod_type
fa_apply_auto_bright

if [ "$(fa_conf DISABLE 0)" = "1" ]; then
    if fa_is_mounted; then
        fa_umount_all && fa_log "DISABLE=1, umount ok"
    fi
    fa_np_unpatch
    fa_fwd_stop
    fa_guard_stop
    fa_sensor_stop
    fa_aod_stop
    fa_modewatch_stop
    killall com.vivo.nightpearl 2>/dev/null
    fa_log "DISABLE=1, full-screen AOD off"
else
    if [ "$(fa_conf MOUNT_SYSFS 1)" = "1" ]; then
        if ! fa_remount; then
            fa_log "action remount failed, try mount_wait"
            fa_mount_wait
        fi
    fi
    if fa_np_patched; then
        fa_log "nightpearl patch applied"
    fi
    killall com.vivo.nightpearl 2>/dev/null
    fa_fwd_stop
    fa_guard_stop
    fa_guard_start
    fa_sensor_stop
    fa_sensor_start
    fa_aod_stop
    fa_aod_start
    fa_modewatch_start
fi

echo "=============================================="
echo " iQOO Neo9S Pro 全屏AOD（KSU 版） v8.2"
echo "=============================================="
echo "读面板串(system_app) : $(runcon u:r:system_app:s0 cat "$SYSFS" 2>&1 | head -c 90)"
echo "假文件标签           : $(fa_label_of "$FAKE")"
echo "当前可见             : $(cat "$SYSFS" 2>/dev/null | head -c 90)"
echo
echo "机型      : $(getprop ro.vivo.product.model) / $(getprop ro.vivo.market.name)"
echo "系统版本  : $(getprop ro.vivo.product.version)"
echo
echo "属性 ro.vivo.keyguard_full_aod.enable = $(getprop ro.vivo.keyguard_full_aod.enable)"
echo "bind mount : $(fa_is_mounted && echo 已挂载 || echo 未挂载)"
echo "挂载行     : $(fa_mount_line | cut -c1-80)"
echo "sysfs 方式 : $(fa_conf SYSFS_MODE auto)   直写标记=$( [ -f "$WORK/sysfs_written" ] && echo yes || echo no )"
echo
echo "配置 ($CONF):"
echo "  SUPPORT_FULL_SCREEN = $(fa_conf SUPPORT_FULL_SCREEN 1)"
echo "  AOD_BRIGHTNESS      = $(fa_conf AOD_BRIGHTNESS '(保持原值)')"
echo "  AOD_TYPE            = $(fa_conf AOD_TYPE '(不改)')"
echo "  SMART_AOD           = $(fa_conf SMART_AOD '(不改)')"
echo "  AUTO_BRIGHT         = $(fa_conf AUTO_BRIGHT 0)"
echo "  BRIGHT_GUARD        = $(fa_conf BRIGHT_GUARD 1)"
echo "  GUARD_DEBUG         = $(fa_conf GUARD_DEBUG 1)"
echo "  DISABLE             = $(fa_conf DISABLE 0)"
echo "  SYSFS_MODE          = $(fa_conf SYSFS_MODE auto)"
echo "  OVERRIDES           = $(fa_conf OVERRIDES)"
echo
echo "原始内容 : $(cat "$ORIG" 2>/dev/null)"
echo "当前可见 : $(cat "$SYSFS" 2>/dev/null)"
echo
echo "原始标签   : $(cat "$ORIG_LABEL_FILE" 2>/dev/null)"
echo "假文件标签 : $(fa_label_of "$FAKE")"
echo "system_app 直接读 : $(runcon u:r:system_app:s0 cat "$SYSFS" 2>&1 | head -c 110)"
echo "SELinux 拒绝记录（应为空）:"
fa_avc_hits | sed 's/^/  /'
echo
echo "Settings:"
echo "  secure vivo_keyguard_aod_type   = $(settings get secure vivo_keyguard_aod_type 2>/dev/null)"
echo "  secure full_screen_aod_enabled  = $(settings get secure full_screen_aod_enabled 2>/dev/null)"
echo "  secure doze_always_on           = $(settings get secure doze_always_on 2>/dev/null)"
echo "  system screen_brightness        = $(settings get system screen_brightness 2>/dev/null)"
echo "  system screen_brightness_float  = $(settings get system screen_brightness_float 2>/dev/null)"
echo "  system screen_brightness_mode   = $(settings get system screen_brightness_mode 2>/dev/null)  (0=手动 1=自动)"
echo
echo "亮度守卫 : $(fa_guard_running && echo 运行中 || echo 未运行)  pid=$(cat "$GUARD_PID" 2>/dev/null)"
echo "守卫日志 : $GUARD_LOG"
tail -n 20 "$GUARD_LOG" 2>/dev/null | sed 's/^/  /'
echo
echo "开机第一现场原厂串（orig_boot）: $(cat "$ORIG_BOOT" 2>/dev/null)"
echo "              原厂标签        : $(cat "$ORIG_BOOT_LABEL" 2>/dev/null)"
echo
echo "AOD 超时 : $(fa_aod_running && echo 运行中 || echo 未运行)  pid=$(cat "$AODK_PID" 2>/dev/null)"
echo "  固定亮度=$(fa_conf AOD_FIX_LEVEL 956)   阶梯=$(fa_conf AOD_STEPS '(空)')   黑档=$(fa_conf AOD_OFF_LEVEL 1)   开关=$(fa_conf AOD_TIMEOUT 1)"
echo "  aod_bl_level 当前 = $(cat "$AOD_BL" 2>/dev/null)   bl_level = $(cat "$BL" 2>/dev/null)"
echo "  日志   : $AODK_LOG"
tail -n 15 "$AODK_LOG" 2>/dev/null | sed 's/^/  /'
echo
echo "传感器桥 : $(fa_sensor_running && echo 运行中 || echo 未运行)  pid=$(cat "$SENSOR_PID" 2>/dev/null)"
echo "  状态   : $(cat "$SENSOR_STATE" 2>/dev/null)"
echo "  日志   : $SENSOR_LOG"
tail -n 10 "$SENSOR_LOG" 2>/dev/null | sed 's/^/  /'
echo
echo "熄屏显示补丁 : $(fa_conf PATCH_APK 1)  base=$(fa_np_base)"
echo "补丁包来源   : $(fa_np_src)"
echo "  版本       : $(fa_np_version)（补丁只对 8.0.4.2 生效）"
echo "  已挂载     : $(fa_np_mounted && echo yes || echo no)"
echo "  本地副本   : $(ls -l "$WORK/nightpearl_patched.apk" 2>/dev/null)"
echo "  进程       : $(ps -A -o PID,ARGS 2>/dev/null | grep "[c]om.vivo.nightpearl" | head -n 1)"
echo
fa_probe
echo
echo "近期 AOD / 通知 / 音乐日志（最近 20 行）:"
fa_recent_log | tail -n 20
echo
echo "===== 面板 / LCM 诊断（发给作者用） ====="
echo "[A] /vendor/etc 里的 panel 文件:"
ls -l /vendor/etc 2>/dev/null | grep -iE 'pd2339|_dbi|panel' | head -n 20
echo "[B] panel_info (/sys/lcm/panel_info):"
cat /sys/lcm/panel_info 2>/dev/null | head -c 500
echo
echo "[C] 内核版本 (/proc/version):"
cat /proc/version 2>/dev/null
echo "[D] lcmctl 文件:"
ls -l /vendor/bin/hw/vendor.vivo.hardware.lcmctl@1.0-service 2>/dev/null
ls -l /vendor/lib64/ 2>/dev/null | grep -i lcmctl
echo "[E] 相关属性:"
getprop 2>/dev/null | grep -iE 'lcm|panel_name|display' | head -n 15
echo
echo "关键设置项（闪退排查用）:"
for k in vivo_keyguard_aod_type screen_off_remind_aod_type full_screen_aod_enabled full_screen_aod_show; do
    echo "  $k = $(settings get secure "$k" 2>/dev/null)"
done
echoecho "aod.log 最后 12 行:"
tail -n 12 "$WORK/aod.log" 2>/dev/null
echo
echo "最近崩溃（logcat -b crash，最后 30 行）:"
logcat -d -b crash -v brief 2>/dev/null | tail -n 30
echo
echo "=============================================="
