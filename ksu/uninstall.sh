#!/system/bin/sh
# ============================================================
# Neo9SP_AOD 卸载脚本 v7.0
#
# 目标：卸载后**不留任何残留**，尤其要覆盖“删模块 + 软重启”这种场景
# （软重启不会重跑 init/ KSU 脚本，bind mount 也会一直留在内核挂载表里）。
#
# 清理清单：
#   1. 停掉所有守护进程（guard / aodkeep / modewatch / sensor bridge / logcat）
#   2. 还原 settings 里被改过的 AOD 类型（vivo_keyguard_aod_type 等）
#   3. 循环 umount 面板串（可能叠了多层）与夜明珠 APK
#   4. 杀掉夜明珠，让它按真实面板串重新初始化
#   5. 删除工作目录、补丁副本、日志
#
# 日志写在 /data/local/tmp/aod_uninstall.log（工作目录会被删掉，所以不能写那里）
# ============================================================

SYSFS=/sys/lcm/aod_disp_info
SYSFS1=/sys/lcm1/aod_disp_info
AOD_BL=/sys/lcm/aod_bl_level
MODID=iqoo_pd2339_fullaod
WORK=/data/adb/$MODID
UNLOG=/data/local/tmp/aod_uninstall.log

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$UNLOG" 2>/dev/null; }

log "==== uninstall start v7.0 ===="

# ---------- 1. 停守护进程 ----------
for p in $(ps -A -o PID,ARGS 2>/dev/null | grep -E "[g]uard\.sh|[a]odkeep\.sh|[m]odewatch|[c]om\.dsh\.aod\.SensorBridge|[l]ogcat -b events" | awk '{print $1}'); do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -9 "$p" 2>/dev/null && log "killed pid $p"
done
rm -f "$WORK"/*.pid 2>/dev/null

# ---------- 2. 清理 settings（删除，不回写） ----------
# 备份可能被污染（首次升级到 v7 时，采到的已经是模块写过的 3/1/1/1），
# 所以卸载一律删除这些键，交回系统默认，才能真正“无残留”。
settings put secure screen_off_remind_aod_type 0 2>/dev/null
log "cleanup settings: screen_off_remind_aod_type -> 0"
for k in vivo_keyguard_aod_type full_screen_aod_enabled full_screen_aod_show; do
    settings delete secure "$k" 2>/dev/null
    log "cleanup settings: delete $k"
done
# 停转发器
for p in $(ps -A -o PID,ARGS 2>/dev/null | grep -E "[f]wd|aodfwd" | awk '{print $1}'); do
    case "$p" in '|*[!0-9]*) continue ;; esac
    kill -9 "$p" 2>/dev/null
done

# ---------- 3. 循环 umount（剥掉叠层） ----------
umount_all() {
    _p="$1"
    _i=0
    while [ $_i -lt 8 ]; do
        grep -q " $_p " /proc/mounts 2>/dev/null || return 0
        umount "$_p" 2>/dev/null || busybox umount "$_p" 2>/dev/null
        _i=$((_i + 1))
        sleep 0.2
    done
    log "umount still busy: $_p"
}

umount_all "$SYSFS"
umount_all "$SYSFS1"
umount_all "$WORK/fs/aod_disp_info"
umount_all "$WORK/fs"
umount_all "$WORK/realsys"
log "panel string unmounted (mounted_left=$(grep -c " $SYSFS " /proc/mounts 2>/dev/null))"

base=$(pm path com.vivo.nightpearl 2>/dev/null | sed 's/package://' | grep -m1 'base.apk')
if [ -n "$base" ]; then
    umount_all "$base"
    log "nightpearl apk unmounted ($base)"
fi

# ---------- 4. 让夜明珠 / SystemUI 按真实串重新初始化 ----------
# 只杀夜明珠时，设置页与锁屏布局可能还缓存着“全屏”的样式，
# 表现为清理完了局部熄屏还是偏左，非要重启一次才好。
# 连 SystemUI 一起重启（会自动拉起），布局与设置页状态就会立刻刷新。
killall com.vivo.nightpearl 2>/dev/null
log "nightpearl killed"
killall com.android.systemui 2>/dev/null
log "systemui restarted"

# ---------- 5. 删文件 ----------
rm -f "$WORK/nightpearl_patched.apk" 2>/dev/null
rm -f "$WORK/aod_disp_info.fake" 2>/dev/null
rm -rf "$WORK" 2>/dev/null
rm -f "/data/adb/${MODID}.log" 2>/dev/null
rm -f /data/local/tmp/nightpearl_patched.apk 2>/dev/null

log "==== uninstall done ===="
