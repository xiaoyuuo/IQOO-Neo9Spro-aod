#!/system/bin/sh
# iQOO Neo9S Pro 全屏AOD —— 公共函数库 (v1.4)
#
# v1.4：面板能力串改成「可配置」—— support_full_screen 的档位和 aod_brightness 都能在
#   /data/adb/iqoo_pd2339_fullaod/config.ini 里改，点 Action 即刻生效，用来试亮度/过渡。
#   并且 Action 会顺带 dump 一段跟亮度、AOD 相关的 logcat，方便定位“先最暗再亮一点”。

MODID=iqoo_pd2339_fullaod
LOG=/data/adb/${MODID}.log
WORK=/data/adb/${MODID}
FAKE=$WORK/aod_disp_info
ORIG=$WORK/orig.txt
ORIG_LABEL_FILE=$WORK/orig_label.txt
CONF=$WORK/config.ini
SYSFS=/sys/lcm/aod_disp_info

FALLBACK='aod_brightness=956,support_full_screen=1,support_1hz=2,doze_suspend_fps=1'

fa_log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

# 把模块自带 config.ini 里新增的键补进已存在的用户配置（老用户升级不会缺键）
fa_conf_sync() {
    [ -f "$MODDIR/config.ini" ] || return 0
    [ -f "$CONF" ] || return 0
    grep -E '^[A-Za-z_]+=' "$MODDIR/config.ini" 2>/dev/null | while IFS= read -r line; do
        k=${line%%=*}
        [ -z "$k" ] && continue
        if ! grep -q "^${k}=" "$CONF" 2>/dev/null; then
            printf '%s\n' "$line" >> "$CONF"
            fa_log "config: add missing key $k"
        fi
    done
}

fa_conf() {
    _k="$1"; _d="$2"
    if [ -f "$CONF" ]; then
        _v=$(grep -m1 "^${_k}=" "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')
        if [ -n "$_v" ]; then
            printf '%s' "$_v"
            return 0
        fi
    fi
    printf '%s' "$_d"
}

fa_resetprop() {
    _n="$1"; _v="$2"
    if [ -x /data/adb/ksu/bin/resetprop ]; then
        /data/adb/ksu/bin/resetprop "$_n" "$_v" && return 0
    fi
    if [ -x /data/adb/ksu/bin/ksud ]; then
        /data/adb/ksu/bin/ksud resetprop "$_n" "$_v" && return 0
    fi
    if command -v resetprop >/dev/null 2>&1; then
        resetprop "$_n" "$_v" && return 0
    fi
    setprop "$_n" "$_v" 2>/dev/null
}

fa_write_props() {
    fa_resetprop ro.vivo.keyguard_full_aod.enable 1
    fa_log "prop ro.vivo.keyguard_full_aod.enable = $(getprop ro.vivo.keyguard_full_aod.enable)"

    # 智能熄屏（依赖摄像头/传感器，静止时冻结画面）开关，留空则不动
    sa=$(fa_conf SMART_AOD "")
    if [ -n "$sa" ]; then
        fa_resetprop persist.vivo.phone.smart_aod "$sa"
        fa_log "prop persist.vivo.phone.smart_aod = $(getprop persist.vivo.phone.smart_aod) (set $sa)"
    fi

    getprop 2>/dev/null | grep -o '^\[[^]]*\]' | tr -d '[]' | grep -i aod | while read -r name; do
        case "$name" in
            *full*|*fullscreen*|*enable*|*support*|*switch*) ;;
            *) continue ;;
        esac
        case "$name" in
            *time*|*Time*|*brightness*|*Brightness*|*count*|*mode*|*level*|*delay*|*size*|*fps*) continue ;;
        esac
        val=$(getprop "$name" 2>/dev/null)
        if [ "$val" = "0" ] || [ -z "$val" ]; then
            fa_resetprop "$name" 1
            fa_log "mirror prop $name : '$val' -> '1'"
        fi
    done
}

fa_label_of() {
    lbl=$(ls -Z "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$lbl" ]; then
        lbl=$(stat -c '%C' "$1" 2>/dev/null)
    fi
    printf '%s' "$lbl"
}

fa_capture_orig_label() {
    if [ ! -s "$ORIG_LABEL_FILE" ]; then
        lbl=$(fa_label_of "$SYSFS")
        if [ -n "$lbl" ]; then
            printf '%s' "$lbl" > "$ORIG_LABEL_FILE" 2>/dev/null
        fi
    fi
}

# 把 content 里的 key=数字 换成新值；没有这个 key 就追加
fa_replace_kv() {
    _c="$1"; _k="$2"; _v="$3"
    case "$_c" in
        *"$_k="*)
            _pre=${_c%%"$_k="*}
            _rest=${_c#*"$_k="}
            case "$_rest" in
                *,*) _suf=",${_rest#*,}" ;;
                *) _suf="" ;;
            esac
            printf '%s' "${_pre}${_k}=${_v}${_suf}"
            ;;
        *)
            if [ -n "$_c" ]; then
                printf '%s,%s=%s' "$_c" "$_k" "$_v"
            else
                printf '%s=%s' "$_k" "$_v"
            fi
            ;;
    esac
}

fa_build_fake() {
    mkdir -p "$WORK" 2>/dev/null
    fa_capture_orig_label

    if [ ! -s "$ORIG" ] && [ -r "$SYSFS" ]; then
        cat "$SYSFS" > "$ORIG" 2>/dev/null
    fi
    base=$(cat "$ORIG" 2>/dev/null)
    [ -z "$base" ] && base=$(cat "$SYSFS" 2>/dev/null)
    [ -z "$base" ] && base="$FALLBACK"

    sfs=$(fa_conf SUPPORT_FULL_SCREEN 1)
    case "$sfs" in
        1|2|3) ;;
        *) sfs=1 ;;
    esac
    content=$(fa_replace_kv "$base" support_full_screen "$sfs")

    br=$(fa_conf AOD_BRIGHTNESS "")
    case "$br" in
        ''|*[!0-9]*) ;;
        *) content=$(fa_replace_kv "$content" aod_brightness "$br") ;;
    esac

    # 任意额外覆盖，逗号分隔，例如 doze_suspend_fps=0,support_1hz=1
    ov=$(fa_conf OVERRIDES "")
    if [ -n "$ov" ]; then
        oldifs=$IFS
        IFS=','
        for kv in $ov; do
            case "$kv" in
                *=*) content=$(fa_replace_kv "$content" "${kv%%=*}" "${kv#*=}") ;;
            esac
        done
        IFS=$oldifs
        fa_log "overrides applied: $ov"
    fi

    printf '%s' "$content" > "$FAKE" 2>/dev/null

    check=$(cat "$FAKE" 2>/dev/null)
    case "$check" in
        *support_full_screen=[123]*) ;;
        *)
            fa_log "self-check failed (got '$check'), write fallback"
            printf '%s' "$FALLBACK" > "$FAKE" 2>/dev/null
            ;;
    esac
    chmod 0644 "$FAKE" 2>/dev/null

    CHCON_OK=0
    lbl=$(cat "$ORIG_LABEL_FILE" 2>/dev/null)
    if [ -n "$lbl" ]; then
        if chcon "$lbl" "$FAKE" 2>>"$LOG"; then
            CHCON_OK=1
            fa_log "chcon ok: $lbl"
        else
            fa_log "chcon FAILED: $lbl"
        fi
    else
        fa_log "chcon skipped: no original label"
    fi
    fa_log "fake aod_disp_info = $(cat "$FAKE" 2>/dev/null)"
}

fa_is_mounted() {
    grep -q " $SYSFS " /proc/mounts 2>/dev/null
}

fa_mount_fake() {
    if [ ! -e "$SYSFS" ]; then
        fa_log "sysfs missing: $SYSFS"
        return 1
    fi
    fa_build_fake
    if [ "$CHCON_OK" != "1" ]; then
        fa_log "SKIP mount: label not set, mounting would break reads"
        return 1
    fi
    if mount --bind "$FAKE" "$SYSFS" 2>>"$LOG"; then
        fa_log "bind mount ok: $SYSFS"
        return 0
    fi
    if command -v busybox >/dev/null 2>&1 && busybox mount --bind "$FAKE" "$SYSFS" 2>>"$LOG"; then
        fa_log "busybox bind mount ok"
        return 0
    fi
    fa_log "bind mount FAILED"
    return 1
}

# 是否伪造面板能力串（0 = 只写属性，不动 /sys/lcm/aod_disp_info）
fa_mount_enabled() {
    [ "$(fa_conf MOUNT_SYSFS 1)" = "1" ]
}

fa_remount() {
    if ! fa_mount_enabled; then
        fa_log "MOUNT_SYSFS=0, skip sysfs"
        return 1
    fi
    if fa_is_mounted; then
        if umount "$SYSFS" 2>>"$LOG"; then
            fa_log "umount ok"
        else
            fa_log "umount FAILED"
            return 1
        fi
    fi
    fa_mount_fake
}

fa_mount_wait() {
    i=0
    while [ $i -lt 40 ]; do
        if [ -e "$SYSFS" ]; then
            fa_mount_fake && return 0
        fi
        i=$((i + 1))
        sleep 0.5 2>/dev/null || sleep 1
    done
    return 1
}

fa_mount_line() {
    grep " $SYSFS " /proc/mounts 2>/dev/null | head -n 1
}

fa_avc_hits() {
    dmesg 2>/dev/null | grep -i "avc" | grep -i "aod_disp_info" | tail -n 5
}

# ---------------- 熄屏显示 APK 补丁（等价于当年 LSPosed 强 f0/e0/Q，但不装框架） ----------------
NP_PKG=com.vivo.nightpearl
NP_VER=8.0.4.2

fa_np_base() {
    _cp=$(dumpsys package "$NP_PKG" 2>/dev/null | grep -m1 'codePath=' | cut -d= -f2 | tr -d ' \r')
    if [ -n "$_cp" ]; then
        printf '%s/base.apk' "$_cp"
        return 0
    fi
    pm path "$NP_PKG" 2>/dev/null | sed 's/package://' | grep -m1 'base.apk'
}

fa_np_version() {
    dumpsys package "$NP_PKG" 2>/dev/null | grep -m1 versionName | cut -d= -f2 | tr -d ' \r'
}

# 找补丁包：模块目录优先，其次 /sdcard/Download 与 /data/local/tmp（方便单独传大文件）
fa_np_src() {
    for p in "$MODDIR/nightpearl_patched.apk" \
             /sdcard/Download/nightpearl_patched.apk \
             /storage/emulated/0/Download/nightpearl_patched.apk \
             /data/local/tmp/nightpearl_patched.apk; do
        if [ -f "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

fa_np_patched() {
    if [ "$(fa_conf PATCH_APK 1)" != "1" ]; then
        fa_log "PATCH_APK=0, skip nightpearl patch"
        return 1
    fi
    npatch=$(fa_np_src)
    if [ -z "$npatch" ]; then
        fa_log "patched apk not found (放 /sdcard/Download/nightpearl_patched.apk 或模块目录)"
        return 1
    fi
    base=$(fa_np_base)
    if [ -z "$base" ]; then
        fa_log "com.vivo.nightpearl base.apk not found"
        return 1
    fi
    ver=$(fa_np_version)
    if [ "$ver" != "$NP_VER" ]; then
        fa_log "nightpearl version '$ver' != '$NP_VER', skip patch (更新后需重新适配)"
        return 1
    fi
    if grep -q " $base " /proc/mounts 2>/dev/null; then
        return 0
    fi
    lbl=$(fa_label_of "$base")
    if [ -n "$lbl" ]; then
        if ! chcon "$lbl" "$npatch" 2>>"$LOG"; then
            fa_log "chcon patched apk FAILED: $lbl"
            return 1
        fi
    fi
    if mount --bind "$npatch" "$base" 2>>"$LOG"; then
        fa_log "patched nightpearl mounted over $base"
        return 0
    fi
    fa_log "mount patched nightpearl FAILED ($base)"
    return 1
}

fa_np_unpatch() {
    base=$(fa_np_base)
    if [ -n "$base" ] && grep -q " $base " /proc/mounts 2>/dev/null; then
        umount "$base" 2>>"$LOG" && fa_log "umount patched nightpearl ok"
    fi
}

# 是否在应用配置后重启「熄屏显示」进程（0 = 保持热进程，用于验证冷启动是否让黑屏变长）
fa_kill_app_enabled() {
    [ "$(fa_conf KILL_APP 1)" = "1" ]
}

# 把 AOD 类型写进 Settings（1=局部 2=融合 3=全屏），开机与 Action 都会调用
fa_apply_aod_type() {
    at=$(fa_conf AOD_TYPE "")
    [ -z "$at" ] && return 0
    case "$at" in
        1|2|3) ;;
        *) fa_log "AOD_TYPE invalid: $at"; return 1 ;;
    esac
    settings put secure vivo_keyguard_aod_type "$at" 2>/dev/null
    fa_log "settings vivo_keyguard_aod_type = $(settings get secure vivo_keyguard_aod_type 2>/dev/null) (want $at)"
}

fa_recent_log() {
    logcat -d 2>/dev/null | grep -i -E "VivoAod|AodViewMediator|AodMusic|KeyguardUpdateMonitor|DozeService|MediaSession|NightPearl|aod_show|notification" \
        | grep -v -E "CompositionEngine|ConfigStore" | tail -n 60
}
