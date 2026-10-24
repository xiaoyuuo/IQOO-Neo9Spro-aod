#!/system/bin/sh
# 「执行 / Action」按钮：按 config.ini 重新应用一次 + 诊断报告
MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
if [ ! -f "$CONF" ] && [ -f "$MODDIR/config.ini" ]; then
    cp "$MODDIR/config.ini" "$CONF" 2>/dev/null
fi

fa_log "==== action: apply (v1.7) ===="
fa_write_props

fa_apply_aod_type

if [ "$(fa_conf DISABLE 0)" = "1" ]; then
    if fa_is_mounted; then
        umount "$SYSFS" 2>>"$LOG" && fa_log "DISABLE=1, umount ok"
    fi
    fa_np_unpatch
    fa_kill_app_enabled && killall com.vivo.nightpearl 2>/dev/null
    fa_log "DISABLE=1, full-screen AOD off"
else
    if ! fa_remount; then
        fa_log "action remount failed, try mount_wait"
        fa_mount_wait
    fi
    if fa_np_patched; then
        fa_log "nightpearl patch applied"
    fi
    fa_kill_app_enabled && killall com.vivo.nightpearl 2>/dev/null
fi

echo "=============================================="
echo " iQOO Neo9S Pro 全屏AOD（KSU 版） v1.7"
echo "=============================================="
echo "机型      : $(getprop ro.vivo.product.model) / $(getprop ro.vivo.market.name)"
echo "系统版本  : $(getprop ro.vivo.product.version)"
echo
echo "属性 ro.vivo.keyguard_full_aod.enable = $(getprop ro.vivo.keyguard_full_aod.enable)"
echo "bind mount : $(fa_is_mounted && echo 已挂载 || echo 未挂载)"
echo "挂载行     : $(fa_mount_line | cut -c1-80)"
echo
echo "配置 ($CONF):"
echo "  SUPPORT_FULL_SCREEN = $(fa_conf SUPPORT_FULL_SCREEN 1)"
echo "  AOD_BRIGHTNESS      = $(fa_conf AOD_BRIGHTNESS '(保持原值)')"
echo "  DISABLE             = $(fa_conf DISABLE 0)"
echo "  OVERRIDES           = $(fa_conf OVERRIDES ')"
echo
echo "原始内容 : $(cat "$ORIG" 2>/dev/null)"
echo "当前可见 : $(cat "$SYSFS" 2>/dev/null)"
echo
echo "原始标签 : $(cat "$ORIG_LABEL_FILE" 2>/dev/null)"
echo "假文件标签 : $(fa_label_of "$FAKE")"
echo "SELinux 拒绝记录（应为空）:"
fa_avc_hits | sed 's/^/  /'
echo
echo "Settings:"
echo "  secure vivo_keyguard_aod_type   = $(settings get secure vivo_keyguard_aod_type 2>/dev/null)"
echo "  secure full_screen_aod_enabled  = $(settings get secure full_screen_aod_enabled 2>/dev/null)"
echo "  secure doze_always_on           = $(settings get secure doze_always_on 2>/dev/null)"
echo
echo "熄屏显示补丁 : $(fa_conf PATCH_APK 1)  base=$(fa_np_base)"
echo "补丁包来源   : $(fa_np_src)"
echo "  版本       : $(fa_np_version)（补丁只对 8.0.4.2 生效）"
echo
echo "近期 AOD / 通知 / 音乐日志（最近 60 行）:"
fa_recent_log | tail -n 60
echo
echo "模块日志尾部 ($LOG):"
tail -n 12 "$LOG" 2>/dev/null
echo "=============================================="
