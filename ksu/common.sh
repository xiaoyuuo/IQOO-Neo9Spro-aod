#!/system/bin/sh
# iQOO Neo9S Pro 全屏AOD —— 公共函数库 (v3.0)
#
# v3.0：修「解锁后亮度卡在熄屏显示那一档」——
#   1) 熄屏显示进程（com.vivo.nightpearl）跑在 system_app 域，原来 sepolicy 只放行了
#      platform_app/untrusted_app，它读不到伪造的面板串 → 回退到「不支持全屏」分支，
#      表现就是「先最暗、再抬一档」的亮度错位。v3.0 补上 system_app 的读权限，
#      并且 chcon 改成「原标签 → system_file → vendor_file」回退，不再因为 chcon 失败就放弃挂载。
#   2) 新增亮度守卫 guard.sh：屏幕点亮/解锁后，把「当前设置的亮度」重新下发一次，
#      把熄屏显示阶段残留的亮度覆盖掉（就是「往上拉一下再往下拉才变暗」那一下）。

MODID=iqoo_pd2339_fullaod
LOG=/data/adb/${MODID}.log
WORK=/data/adb/${MODID}
FAKE=$WORK/aod_disp_info
ORIG=$WORK/orig.txt
ORIG_LABEL_FILE=$WORK/orig_label.txt
ORIG_BOOT=$WORK/orig_boot.txt
ORIG_BOOT_LABEL=$WORK/orig_boot_label.txt
CONF=$WORK/config.ini
SYSFS=/sys/lcm/aod_disp_info
# v7.7：不同机型 AOD 背光节点不一样（Neo7 上 /sys/lcm/aod_bl_level 写入被拒），
# 这里探测一个"写得进去"的节点；探测失败再退回默认路径。
AOD_BL=/sys/lcm/aod_bl_level
fa_pick_aod_bl() {
    for _n in /sys/lcm/aod_bl_level /sys/lcm1/aod_bl_level /sys/lcm/vlcm_aod_bl_level; do
        [ -e "$_n" ] || continue
        _cur=$(cat "$_n" 2>/dev/null | tr -d ' \r\n')
        case "$_cur" in
            user=*) _cur=${_cur#user=}; _cur=${_cur%%,*} ;;
        esac
        case "$_cur" in ''|*[!0-9]*) _cur=0 ;; esac
        printf '%s' "$_cur" > "$_n" 2>/dev/null && { AOD_BL="$_n"; return 0; }
    done
    return 1
}
BL=/sys/lcm/bl_level

FALLBACK='aod_brightness=956,support_full_screen=1,support_1hz=2,doze_suspend_fps=1'

fa_log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

# 把某个键设成指定值（不存在就追加）
fa_conf_set() {
    _k="$1"; _v="$2"
    [ -f "$CONF" ] || return 0
    awk -v k="$_k" -v v="$_v" '
        $0 ~ "^" k "=" { if (!done) { print k "=" v; done=1 } ; next }
        { print }
        END { if (!done) print k "=" v }
    ' "$CONF" > "${CONF}.tmp" 2>/dev/null && mv "${CONF}.tmp" "$CONF" 2>/dev/null
    rm -f "${CONF}.tmp" 2>/dev/null
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

    # v3.0：老配置里 SMART_AOD= 是空的（"留空=不改"），升级后按新默认值补上，
    # 否则「智能熄屏」这条新功能对老用户等于没加。
    for _k in SMART_AOD BRIGHT_GUARD GUARD_DEBUG AUTO_BRIGHT; do
        _dl=$(grep -m1 "^${_k}=" "$MODDIR/config.ini" 2>/dev/null)
        [ -z "$_dl" ] && continue
        _dv=${_dl#*=}
        [ -z "$_dv" ] && continue
        _cl=$(grep -m1 "^${_k}=" "$CONF" 2>/dev/null)
        if [ -n "$_cl" ] && [ -z "${_cl#*=}" ]; then
            fa_conf_set "$_k" "$_dv"
            fa_log "config: fill empty $_k = $_dv"
        fi
    done

    # 一次性迁移到 5.2：
    #   实测面板串的 aod_brightness 对全屏 AOD 亮度无效（956 / 4000 都是最暗），
    #   真正管 AOD 亮度的是 /sys/lcm/aod_bl_level。所以改成：
    #   - AOD_BRIGHTNESS 留空（保持原厂 956，不再乱改面板串）；
    #   - 启动 AOD 守护，但只用「固定亮度」模式（AOD_FIX_LEVEL=956），不跑阶梯；
    #   - 传感器桥 / 亮度守卫 / 自动亮度 继续关着。
    _verf="$WORK/ver"
    _cv=$(cat "$_verf" 2>/dev/null)
    if [ "$_cv" != "5.2" ]; then
        for _k in SENSOR_BRIDGE BRIGHT_GUARD AUTO_BRIGHT; do
            _cur=$(grep -m1 "^${_k}=" "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')
            if [ "$_cur" = "1" ]; then
                fa_conf_set "$_k" 0
                fa_log "migrate 5.2: $_k 1 -> 0"
            fi
        done
        fa_conf_set AOD_TIMEOUT 1
        fa_conf_set AOD_STEPS ""
        if [ -z "$(grep -m1 '^AOD_FIX_LEVEL=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')" ]; then
            fa_conf_set AOD_FIX_LEVEL 956
        fi
        if [ -n "$(grep -m1 '^AOD_BRIGHTNESS=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')" ]; then
            fa_conf_set AOD_BRIGHTNESS ""
            fa_log "migrate 5.2: AOD_BRIGHTNESS cleared (该键对全屏AOD无效)"
        fi
        printf '5.2' > "$_verf" 2>/dev/null
    fi

    # 一次性迁移到 5.6：
    #   补丁 APK 在这台机器上装不上（安装报 -911），bind mount 也挂不上，
    #   所以放弃补丁路线，PATCH_APK 改回 0；设置页的「局部/全屏」选择器交给 LSPosed。
    if [ "$(cat "$_verf" 2>/dev/null)" != "5.6" ]; then
        if [ "$(grep -m1 '^PATCH_APK=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')" = "1" ]; then
            fa_conf_set PATCH_APK 0
            fa_log "migrate 5.6: PATCH_APK 1 -> 0 (补丁包装不上/挂不上，改用 LSPosed 提供入口)"
        fi
        printf '5.6' > "$_verf" 2>/dev/null
    fi

    # 一次性迁移到 5.9：
    #   恢复「15s 暗一档 → 60s 再暗 → 300s 熄灭」的阶梯，并开启传感器桥，
    #   这样到点才能真正熄屏（goToSleep 失败时退化成 input keyevent 223）。
    #   AOD_FIX_LEVEL 归零，改由阶梯第一步写 base(956) 来保证亮度。
    if [ "$(cat "$_verf" 2>/dev/null)" != "5.9" ]; then
        fa_conf_set AOD_FIX_LEVEL 0
        fa_conf_set AOD_STEPS "15:85,60:70,300:1"
        fa_conf_set AOD_TIMEOUT 1
        if [ "$(grep -m1 '^SENSOR_BRIDGE=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')" != "1" ]; then
            fa_conf_set SENSOR_BRIDGE 1
        fi
        fa_log "migrate 5.9: ladder restored + sensor bridge on (到点真熄屏)"
        printf '5.9' > "$_verf" 2>/dev/null
    fi

    # 一次性迁移到 7.1（低功耗）：
    #   5.9 默认打开了传感器桥，它每秒写 sensor.state、持续监听光线/加速度，
    #   是待机耗电的大头；AOD_DEBUG=1 又会把每个事件写进日志（通知洪流时尤其费电）。
    #   7.1 默认都关掉，想要功能再手动打开。
    if [ "$(cat "$_verf" 2>/dev/null)" != "7.1" ]; then
        fa_conf_set SENSOR_BRIDGE 0
        fa_conf_set AOD_DEBUG 0
        fa_conf_set GUARD_DEBUG 0
        grep -q '^AOD_NOTIFY_RESET=' "$CONF" 2>/dev/null || fa_conf_set AOD_NOTIFY_RESET 0
        grep -q '^MODEWATCH_SEC=' "$CONF" 2>/dev/null || fa_conf_set MODEWATCH_SEC 30
        fa_log "migrate 7.1: low-power defaults (bridge off, debug off, notify reset off)"
        printf '7.1' > "$_verf" 2>/dev/null
    fi

    # 一次性迁移到 7.3（再省电）：
    #   - 熄灭时间 5 分钟 -> 3 分钟（AOD 亮着就是耗电，越早熄越省）
    #   - 关掉 AOD 类型监视（每 30 秒一次 settings 调用；要切类型时点一次「执行」即可）
    if [ "$(cat "$_verf" 2>/dev/null)" != "7.3" ]; then
        _st=$(grep -m1 '^AOD_STEPS=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')
        case "$_st" in
            "15:85,60:70,300:1"|"15:85,60:70,300:1 "|"") fa_conf_set AOD_STEPS "60:70,180:1" ;;
        esac
        fa_conf_set MODEWATCH 0
        fa_log "migrate 7.3: AOD_STEPS 60:70,180:1 / MODEWATCH=0 (省电)"
        printf '7.3' > "$_verf" 2>/dev/null
    fi

    # 一次性迁移到 7.4：
    #   用户明确要求保留「歌词 / 时间 / 消息」实时刷新。
    #   前两者是夜明珠自己刷新的，与模块无关；「来消息重置计时」需要订阅通知，
    #   把它开回来（仍然不写调试日志，避免通知洪流刷盘）。
    if [ "$(cat "$_verf" 2>/dev/null)" != "7.4" ]; then
        fa_conf_set AOD_NOTIFY_RESET 1
        fa_log "migrate 7.4: AOD_NOTIFY_RESET=1 (消息到达时重新计时)"
        printf '7.4' > "$_verf" 2>/dev/null
    fi
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
        case "$lbl" in
            *adb_data_file*) lbl="" ;;   # 已挂载时抓到的是假标签，不要存
        esac
        if [ -n "$lbl" ]; then
            printf '%s' "$lbl" > "$ORIG_LABEL_FILE" 2>/dev/null
        fi
    fi
}

# 开机第一现场：post-fs-data 里、还没挂载时抓一份「真·原厂串 + 真标签」。
# 这份文件每次开机都会重写，永远可信，用来对照 / 兜底。
fa_capture_boot_orig() {
    if fa_is_mounted; then
        fa_log "boot_orig: already mounted, skip"
        return 1
    fi
    _c=$(cat "$SYSFS" 2>/dev/null)
    if [ -z "$_c" ]; then
        fa_log "boot_orig: $SYSFS empty/unreadable"
        return 1
    fi
    printf '%s' "$_c" > "$ORIG_BOOT" 2>/dev/null
    _l=$(fa_label_of "$SYSFS")
    [ -n "$_l" ] && printf '%s' "$_l" > "$ORIG_BOOT_LABEL" 2>/dev/null
    fa_log "boot_orig: '$_c' label='$_l'"
}

# 在「没有挂载」的状态下重新采集原厂内容与标签。
# 修 v2.9~v3.0 的脏数据：如果 ORIG/ORIG_LABEL 是在挂载状态下抓的，
# 会得到 content=support_full_screen=1 且 label=adb_data_file，
# 于是 chcon 变成空操作、原始内容也永远显示“已经是 1”。
fa_refresh_orig() {
    if [ -f "$WORK/sysfs_written" ]; then
        fa_log "refresh_orig: sysfs_written marker present, keep boot_orig"
        [ -s "$ORIG_BOOT" ] && cp "$ORIG_BOOT" "$ORIG" 2>/dev/null
        return 1
    fi
    if fa_is_mounted; then
        fa_log "refresh_orig: still mounted, fallback to boot_orig"
        if [ -s "$ORIG_BOOT" ]; then
            cp "$ORIG_BOOT" "$ORIG" 2>/dev/null
            [ -s "$ORIG_BOOT_LABEL" ] && cp "$ORIG_BOOT_LABEL" "$ORIG_LABEL_FILE" 2>/dev/null
            fa_log "refresh_orig: restored from boot_orig '$(cat "$ORIG" 2>/dev/null)' label='$(cat "$ORIG_LABEL_FILE" 2>/dev/null)'"
        fi
        return 1
    fi
    _c=$(cat "$SYSFS" 2>/dev/null)
    case "$_c" in
        *support_full_screen=?*) ;;
        *) fa_log "refresh_orig: cannot read $SYSFS ('$_c')"; return 1 ;;
    esac
    printf '%s' "$_c" > "$ORIG" 2>/dev/null
    _l=$(fa_label_of "$SYSFS")
    case "$_l" in
        ''|*adb_data_file*)
            fa_log "refresh_orig: label '$_l' suspicious, keep old"
            ;;
        *)
            printf '%s' "$_l" > "$ORIG_LABEL_FILE" 2>/dev/null
            ;;
    esac
    fa_log "refresh_orig: content='$_c' label='$_l'"
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
    # v8.0：优先取真实节点（私有 sysfs 挂载），避免拿到我们自己的假串
    base=$(fa_real_read 2>/dev/null)
    [ -z "$base" ] && base=$(cat "$ORIG" 2>/dev/null)
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
    chmod 0666 "$FAKE" 2>/dev/null

    # v4.7 关键修正：原节点的真实标签是 u:object_r:sysfs_oled_hbm:s0
    # （见 vendor/etc/selinux/vendor_file_contexts:
    #   /sys/lcm/aod_disp_info  u:object_r:sysfs_oled_hbm:s0
    #   /sys/lcm(/.*)?          u:object_r:vivo_lcmfs:s0
    #   init.vivo.rc: chmod 0666 /sys/lcm/aod_disp_info）
    # 以前副本被标成 adb_data_file，SurfaceFlinger / 显示 HAL / 夜明珠都读不到，
    # 所以“AOD 能显示但亮度、超时全不对”。这里按真实标签对齐，不再靠 sepolicy 硬放行。
    CHCON_OK=0
    CHCON_USED=""
    lbl=$(cat "$ORIG_LABEL_FILE" 2>/dev/null)
    case "$lbl" in *adb_data_file*) lbl="" ;; esac
    for _l in "u:object_r:sysfs_oled_hbm:s0" "$lbl" "u:object_r:vivo_lcmfs:s0" "u:object_r:vendor_file:s0" "u:object_r:system_file:s0"; do
        [ -z "$_l" ] && continue
        if chcon "$_l" "$FAKE" 2>>"$LOG"; then
            CHCON_OK=1
            CHCON_USED="$_l"
            break
        fi
        fa_log "chcon FAILED: $_l"
    done
    if [ "$CHCON_OK" = "1" ]; then
        fa_log "chcon ok: $CHCON_USED"
    else
        fa_log "chcon all FAILED, keep adb_data_file (sepolicy 已放行 system_app/platform_app 读取)"
    fi
    fa_log "fake aod_disp_info = $(cat "$FAKE" 2>/dev/null) label=$(fa_label_of "$FAKE")"
}

fa_is_mounted() {
    grep -q " $SYSFS " /proc/mounts 2>/dev/null
}

# 反复 umount，剥掉可能叠了多层的 bind mount（v3.1 日志里出现过
# “umount ok 但 /proc/mounts 里还在”的情况）
fa_umount_all() {
    _i=0
    while [ $_i -lt 6 ]; do
        fa_is_mounted || return 0
        umount "$SYSFS" 2>>"$LOG" || busybox umount "$SYSFS" 2>>"$LOG"
        _i=$((_i + 1))
        sleep 0.3
    done
    fa_is_mounted && return 1
    return 0
}

fa_mount_fake() {
    if [ ! -e "$SYSFS" ]; then
        fa_log "sysfs missing: $SYSFS"
        return 1
    fi
    if fa_is_mounted; then
        fa_log "already mounted, skip duplicate mount"
        return 0
    fi
    fa_build_fake
    # v3.0：chcon 失败也照样挂。sepolicy 已经放行 system_app/platform_app/untrusted_app
    # 读 adb_data_file，所以标签没改成功也能读到；反倒是「不挂」会让全屏 AOD 直接退化。
    if [ "$CHCON_OK" != "1" ]; then
        fa_log "WARN: label not set ($CHCON_USED), mount anyway (sepolicy covers adb_data_file)"
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
# ---------------- v8.0：布局写转发守护 ----------------
fa_fwd_stop() {
    _p=$(cat "$WORK/fwd.pid" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) _p="" ;; esac
    [ -n "$_p" ] && kill -KILL "$_p" 2>/dev/null
    rm -f "$WORK/fwd.pid" 2>/dev/null
}

fa_fwd_running() {
    _p=$(cat "$WORK/fwd.pid" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_p" 2>/dev/null || return 1
    if [ -r "/proc/$_p/cmdline" ]; then
        tr '\0' ' ' < "/proc/$_p/cmdline" | grep -q "aodfwd" || return 1
    fi
    return 0
}

fa_fwd_start() {
    [ "$(fa_conf FWD_LAYOUT 1)" = "1" ] || { fa_log "FWD_LAYOUT=0, skip"; return 0; }
    fa_fwd_running && { fa_log "forwarder already running"; return 0; }
    fa_build_fake
    # v8.2：自适应轮询——刚转发过的 5 个周期内用 0.3s（抓布局变化），
    # 之后退到 2s 空闲（每秒 2 次唤醒对 AOD 待机是有成本的）。
    (
        _idle=0
        while true; do
            if fa_fwd_once; then
                _idle=0
            else
                _idle=$((_idle + 1))
            fi
            if [ "$_idle" -ge 5 ]; then
                sleep 2
            else
                sleep 0.3
            fi
        done
    ) >/dev/null 2>>"$LOG" &
    echo $! > "$WORK/fwd.pid" 2>/dev/null
    fa_log "forwarder started pid=$(cat "$WORK/fwd.pid" 2>/dev/null)"
}

fa_mount_enabled() {
    [ "$(fa_conf MOUNT_SYSFS 1)" = "1" ]
}

# v4.6：直接用「写」的方式改真节点，不做 bind mount。
# 好处：节点的 SELinux 标签保持原样，vendor 显示 HAL 也能读到；
# 我们之前 bind mount 过来的副本标签是 adb_data_file，HAL 很可能读不到，
# 这解释了“能显示但亮度/超时全不对”。
fa_write_direct() {
    if [ ! -e "$SYSFS" ]; then
        fa_log "direct: sysfs missing"
        return 1
    fi
    if fa_is_mounted; then
        fa_umount_all || return 1
    fi
    _want=$(cat "$FAKE" 2>/dev/null)
    [ -z "$_want" ] && { fa_log "direct: fake empty"; return 1; }
    _old=$(cat "$SYSFS" 2>/dev/null)

    printf '%s' "$_want" > "$SYSFS" 2>>"$LOG"
    _rb=$(cat "$SYSFS" 2>/dev/null)
    if [ "$_rb" = "$_want" ]; then
        fa_log "direct write ok (no mount): $_rb"
        : > "$WORK/sysfs_written" 2>/dev/null
        return 0
    fi

    printf '%s\n' "$_want" > "$SYSFS" 2>>"$LOG"
    _rb=$(cat "$SYSFS" 2>/dev/null)
    if [ "$_rb" = "$_want" ]; then
        fa_log "direct write ok (with newline): $_rb"
        : > "$WORK/sysfs_written" 2>/dev/null
        return 0
    fi

    fa_log "direct write rejected (readback='$_rb')"
    if [ -n "$_old" ]; then
        printf '%s' "$_old" > "$SYSFS" 2>/dev/null
        fa_log "restored original: $(cat "$SYSFS" 2>/dev/null)"
    fi
    return 1
}

# 统一入口：auto=先尝试直接写，不行再 bind mount；write=只写；mount=只挂
# ---------------- v8.0：tmpfs + context 伪造节点（X100s 同款思路） ----------------
# 为什么换：/data 副本 chcon 经常失败（ksu 域没有 relabelto 权限），
# 副本最终落在 vendor_file / adb_data_file 上，system_app 读不到 → 只能靠 LSPosed。
# tmpfs 用 -o context= 指定标签，挂进来就带正确标签，夜明珠自己就能读到。
FA_FS="$WORK/fs"
FA_REAL="$WORK/realsys"
FA_REALNODE=""

# 另挂一份 sysfs 看真实节点（不受我们自己 bind 的影响），也能往真节点写
fa_priv_sysfs() {
    [ -n "$FA_REALNODE" ] && [ -e "$FA_REALNODE" ] && return 0
    while umount "$FA_REAL" 2>/dev/null; do :; done
    while umount -l "$FA_REAL" 2>/dev/null; do :; done
    rm -rf "$FA_REAL"; mkdir -p "$FA_REAL" 2>/dev/null
    mount -t sysfs sysfs "$FA_REAL" 2>>"$LOG" || return 1
    FA_REALNODE="$FA_REAL/lcm/aod_disp_info"
    [ -e "$FA_REALNODE" ]
}

fa_real_read() {
    if fa_priv_sysfs; then
        cat "$FA_REALNODE" 2>/dev/null
    else
        cat "$SYSFS" 2>/dev/null
    fi
}

fa_mount_tmpfs() {
    fa_umount_all
    while umount "$FA_FS" 2>/dev/null; do :; done
    while umount -l "$FA_FS" 2>/dev/null; do :; done
    rm -rf "$FA_FS"; mkdir -p "$FA_FS" 2>/dev/null
    _ctx=$(fa_label_of "$SYSFS" 2>/dev/null)
    case "$_ctx" in
        u:object_r:*) ;;
        *) _ctx="u:object_r:sysfs_oled_hbm:s0" ;;
    esac
    if ! mount -t tmpfs -o "context=$_ctx,mode=0777,size=64k" tmpfs "$FA_FS" 2>>"$LOG"; then
        fa_log "tmpfs mount FAILED (context=$_ctx)"
        return 1
    fi
    printf '%s' "$(cat "$FAKE" 2>/dev/null)" > "$FA_FS/aod_disp_info" 2>/dev/null
    chmod 0666 "$FA_FS/aod_disp_info" 2>/dev/null
    if mount --bind "$FA_FS/aod_disp_info" "$SYSFS" 2>>"$LOG"; then
        fa_log "tmpfs overlay ok (context=$_ctx)"
        : > "$WORK/sysfs_tmpfs" 2>/dev/null
        return 0
    fi
    fa_log "tmpfs bind FAILED"
    return 1
}

# 把 App 写进假节点的内容（AOD 布局坐标）转发给真节点，再把假串写回去
fa_fwd_once() {
    [ -e "$SYSFS" ] || return 1
    fa_priv_sysfs || return 1
    # 用 read 内建读，避免每 0.5 秒 fork 两个 cat
    _canon=""
    IFS= read -r _canon < "$FAKE" 2>/dev/null
    [ -z "$_canon" ] && return 1
    _cur=""
    IFS= read -r _cur < "$SYSFS" 2>/dev/null
    [ -z "$_cur" ] && return 1
    [ "$_cur" = "$_canon" ] && return 1
    # 只转发"坐标载荷"（纯数字+空格，形如 1 2 3 4 5 6）；
    # 带 '=' 的是能力串回读/误写，不往真节点写，免得驱动收到垃圾。
    case "$_cur" in
        *[!0-9\ ]*) _payload=0 ;;
        *) _payload=1 ;;
    esac
    if [ "$_payload" = "1" ]; then
        printf '%s' "$_cur" > "$FA_REALNODE" 2>>"$LOG"
    else
        fa_log "skip forward (not a coord payload): $(printf '%s' "$_cur" | cut -c1-30)"
    fi
    # v8.1：先截断再写回，否则 App 写的短内容会在文件尾部留下旧的残留字节，
    # 夜明珠再读就会拿到“半截坐标 + 半截能力串”，解析异常甚至崩设置页。
    : > "$SYSFS" 2>/dev/null
    printf '%s' "$_canon" > "$SYSFS" 2>>"$LOG"
    fa_log "forward len=$(printf '%s' "$_cur" | wc -c) -> real node: $(printf '%s' "$_cur" | cut -c1-40)"
    return 0
}

fa_apply_sysfs() {
    if [ ! -e "$SYSFS" ]; then
        fa_log "sysfs missing: $SYSFS"
        return 1
    fi
    fa_build_fake
    fa_priv_sysfs || fa_log "priv sysfs unavailable, forwarding disabled"
    case "$(fa_conf SYSFS_MODE tmpfs)" in
        write)
            fa_write_direct
            return $?
            ;;
        mount)
            fa_mount_fake
            return $?
            ;;
        *)
            if fa_mount_tmpfs; then
                return 0
            fi
            fa_log "tmpfs failed, fallback to chcon + bind"
            fa_mount_fake
            return $?
            ;;
    esac
}

fa_remount() {
    if ! fa_mount_enabled; then
        fa_log "MOUNT_SYSFS=0, skip sysfs"
        return 1
    fi
    if fa_umount_all; then
        fa_log "umount all ok"
    else
        fa_log "umount still busy, will fallback to boot_orig"
    fi
    # 卸掉之后再抓一次原厂串/标签，保证不是“挂着自己”抓到的脏数据
    fa_refresh_orig
    fa_apply_sysfs
}

fa_mount_wait() {
    i=0
    while [ $i -lt 40 ]; do
        if [ -e "$SYSFS" ]; then
            fa_apply_sysfs && return 0
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
    {
        dmesg 2>/dev/null
        logcat -d -b events 2>/dev/null
        logcat -d -b main 2>/dev/null
    } | grep -i "avc: *denied" \
      | grep -i -E "aod_disp_info|nightpearl|systemuiplugin" \
      | tail -n 8
}

# 诊断探针：回答“为什么 settings 写不进去 / AOD 亮度能不能直接控 / 到底装了没装 LSPosed”
fa_probe() {
    echo "==================== 探针 v3.1 ===================="
    echo "[1] /sys/lcm 节点与权限"
    ls -l /sys/lcm/ 2>/dev/null | sed -n '1,40p'
    for f in aod_disp_info vlcm_bl_level vlcm_aod_bl_level oled_hbm panel_info panel_name; do
        if [ -e "/sys/lcm/$f" ]; then
            echo "  $f = $(cat "/sys/lcm/$f" 2>/dev/null | head -c 160)"
        fi
    done
    echo
    echo "[2] settings 写入通道（4 种方式，全部只写回原值）"
    _b=$(settings get system screen_brightness 2>/dev/null)
    echo "  当前 screen_brightness = ${_b:-<空>}"
    _o=$(settings put system screen_brightness "$_b" 2>&1); echo "  A root settings put : rc=$? ${_o}"
    _o=$(cmd settings put system screen_brightness "$_b" 2>&1); echo "  B cmd settings put  : rc=$? ${_o}"
    if command -v setpriv >/dev/null 2>&1; then
        _o=$(setpriv --reuid 2000 --regid 2000 --clear-groups settings put system screen_brightness "$_b" 2>&1)
        echo "  C setpriv(uid2000)  : rc=$? ${_o}"
    else
        echo "  C setpriv           : 不存在"
    fi
    if command -v su >/dev/null 2>&1; then
        _o=$(su 2000 -c "settings put system screen_brightness $_b" 2>&1); echo "  D su 2000           : rc=$? ${_o}"
    else
        echo "  D su                : 不存在"
    fi
    echo
    echo "[3] 背光 class 节点"
    for f in /sys/class/backlight/*/brightness; do
        [ -e "$f" ] && echo "  $f = $(cat "$f" 2>/dev/null)"
    done
    echo
    echo "[4] 电源 / 显示状态"
    dumpsys power 2>/dev/null | grep -m8 -E "mWakefulness|mIsPowered|mDisplayReady|Display Power"
    dumpsys display 2>/dev/null | grep -m8 -E "Display State|mScreenBrightnessSetting|mScreenBrightnessDoze|mDisplayState|mState="
    echo
    echo "[4b] 与 AOD / 熄屏 / 亮度相关的 Settings（找原厂超时键）"
    settings list secure 2>/dev/null | grep -i -E "aod|doze|screen_off|dim|keyguard|brightness" | head -n 30
    settings list system 2>/dev/null | grep -i -E "aod|doze|screen_off|dim|brightness" | head -n 30
    settings list global 2>/dev/null | grep -i -E "aod|doze|smart" | head -n 20
    echo "  关键三个："
    echo "    vivo_keyguard_aod_type     = $(settings get secure vivo_keyguard_aod_type 2>/dev/null)"
    echo "    screen_off_remind_aod_type = $(settings get secure screen_off_remind_aod_type 2>/dev/null)"
    echo "    doze_always_on             = $(settings get secure doze_always_on 2>/dev/null)"
    echo
    echo "[5] LSPosed / AOD 补丁"
    ls -d /data/adb/lspd /data/adb/modules/*lsp* 2>/dev/null
    echo "  补丁包来源 : $(fa_np_src)"
    echo "  nightpearl : $(fa_np_version)"
    echo
    echo "[6] 原厂串（当前 ORIG 文件）"
    echo "  $(cat "$ORIG" 2>/dev/null)"
    echo "  label: $(cat "$ORIG_LABEL_FILE" 2>/dev/null)"
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

    # v5.4 关键修复：/sdcard 是 FUSE 挂载，不能直接 bind mount 到 /system。
    # 先复制到 /data（ext4/f2fs）再挂，否则 mount 会失败、补丁静默不生效。
    case "$npatch" in
        /sdcard/*|/storage/*)
            _dst=$WORK/nightpearl_patched.apk
            if [ ! -f "$_dst" ] || [ "$npatch" -nt "$_dst" ] 2>/dev/null; then
                fa_log "copy patched apk from $npatch to $_dst"
                cp -f "$npatch" "$_dst" 2>>"$LOG"
            fi
            if [ -f "$_dst" ]; then
                npatch="$_dst"
            else
                fa_log "copy patched apk FAILED"
                return 1
            fi
            ;;
    esac

    # 复制过来的文件默认是 root:root 0600，system 进程读不了，必须放开
    chmod 0644 "$npatch" 2>/dev/null

    # 标签：依次尝试 base.apk 原标签 → vendor_file → system_file，
    # 全部失败也照样挂（不会再因为 chcon 失败而静默放弃）。
    _ok=0
    for _l in "$(fa_label_of "$base")" "u:object_r:vendor_file:s0" "u:object_r:system_file:s0"; do
        [ -z "$_l" ] && continue
        if chcon "$_l" "$npatch" 2>>"$LOG"; then
            fa_log "chcon patched apk ok: $_l"
            _ok=1
            break
        fi
        fa_log "chcon patched apk FAILED: $_l"
    done
    [ "$_ok" = "1" ] || fa_log "chcon all failed, mount anyway (label=$(fa_label_of "$npatch"))"

    if mount --bind "$npatch" "$base" 2>>"$LOG"; then
        sleep 0.5
        if grep -q " $base " /proc/mounts 2>/dev/null; then
            fa_log "patched nightpearl mounted over $base (from $npatch, label=$(fa_label_of "$npatch"))"
            return 0
        fi
        fa_log "mount returned 0 but not in /proc/mounts ($base)"
        return 1
    fi
    fa_log "mount patched nightpearl FAILED ($base from $npatch)"
    return 1
}

fa_np_mounted() {
    _b=$(fa_np_base)
    [ -n "$_b" ] && grep -q " $_b " /proc/mounts 2>/dev/null
}

fa_np_unpatch() {
    base=$(fa_np_base)
    if [ -n "$base" ] && grep -q " $base " /proc/mounts 2>/dev/null; then
        umount "$base" 2>>"$LOG" && fa_log "umount patched nightpearl ok"
    fi
}

# 把 AOD 类型写进 Settings（1=局部 2=融合 3=全屏），开机与 Action 都会调用
# ---------------- v7.0 设置备份 / 还原（卸载不留残留） ----------------
# 模块会改 settings 里的 AOD 类型，卸载时必须还原成用户原来的值。
# 首次运行（post-fs-data）备份一次，卸载脚本读它写回。
fa_backup_settings() {
    _f="$WORK/orig_settings.txt"
    # 开机早期 settings 服务可能还没起来，备份会是空值；
    # 只有已备份到非空的 vivo_keyguard_aod_type 才算数，否则重新采一次。
    if [ -s "$_f" ] && grep -q "^vivo_keyguard_aod_type=..*" "$_f" 2>/dev/null; then
        return 0
    fi
    mkdir -p "$WORK" 2>/dev/null
    : > "$_f" 2>/dev/null
    for _k in vivo_keyguard_aod_type screen_off_remind_aod_type full_screen_aod_enabled full_screen_aod_show; do
        _v=$(settings get secure "$_k" 2>/dev/null | tr -d ' \r\n')
        echo "${_k}=${_v}" >> "$_f" 2>/dev/null
    done
    fa_log "settings backup: $(tr '\n' ' ' < "$_f" 2>/dev/null)"
}

fa_restore_settings() {
    # v7.6：screen_off_remind_aod_type 不能直接删——部分 Settings/夜明珠版本
    # 读这个键时不做 null 兜底，删掉后进「设置 → 熄屏显示」会闪退。
    # 改成写回一个合法的原厂值（0=局部），其余我们自己造出来的键才删除。
    settings put secure screen_off_remind_aod_type 0 2>/dev/null
    fa_log "cleanup settings: screen_off_remind_aod_type -> 0"
    for _k in vivo_keyguard_aod_type full_screen_aod_enabled full_screen_aod_show; do
        settings delete secure "$_k" 2>/dev/null
        fa_log "cleanup settings: delete $_k"
    done
}

fa_apply_aod_type() {
    # v7.5：默认不再写 vivo_keyguard_aod_type。
    # 这个键只影响 AOD 窗口 title，写它反而可能让设置页/夜明珠状态不一致（闪退）。
    # 需要强制类型时把 config 里的 APPLY_AOD_TYPE 改成 1。
    if [ "$(fa_conf APPLY_AOD_TYPE 0)" != "1" ]; then
        return 0
    fi
    at=$(fa_conf AOD_TYPE "")
    [ -z "$at" ] && return 0
    case "$at" in
        1|2|3) ;;
        *) fa_log "AOD_TYPE invalid: $at"; return 1 ;;
    esac
    settings put secure vivo_keyguard_aod_type "$at" 2>/dev/null
    fa_log "settings vivo_keyguard_aod_type = $(settings get secure vivo_keyguard_aod_type 2>/dev/null) (want $at)"
}

# 当前 AOD 类型（1=局部 2=融合 3=全屏），读不到返回空
fa_current_aod_type() {
    # v7.2：真正决定「局部/全屏」的是 screen_off_remind_aod_type（0=局部 1=全屏），
    # vivo_keyguard_aod_type 只影响 AOD 窗口 title。旧版优先读后者，
    # 导致用户在设置里选「局部」时，面板串仍按全屏处理 → 时钟偏左、不居中。
    _r=$(settings get secure screen_off_remind_aod_type 2>/dev/null | tr -d ' \r\n')
    case "$_r" in
        0) printf '1'; return 0 ;;   # 局部
        1) printf '3'; return 0 ;;   # 全屏
    esac
    _t=$(settings get secure vivo_keyguard_aod_type 2>/dev/null | tr -d ' \r\n')
    case "$_t" in
        1|2|3) printf '%s' "$_t"; return 0 ;;
    esac
}

# v6.0：盯着 AOD 类型变化，切到「局部」就把面板串改回 support_full_screen=0
# 并重启夜明珠，让它按原厂局部布局重新排（时钟居中、随机挪位防烧屏）。
fa_modewatch_stop() {
    _p=$(cat "$WORK/modewatch.pid" 2>/dev/null)
    if [ -n "$_p" ]; then
        kill "$_p" 2>/dev/null
        rm -f "$WORK/modewatch.pid" 2>/dev/null
    fi
    return 0
}

fa_modewatch_start() {
    [ "$(fa_conf MODEWATCH 1)" = "1" ] || { fa_log "MODEWATCH=0, skip"; return 0; }
    _mw=$(fa_conf MODEWATCH_SEC 30)
    case "$_mw" in ''|*[!0-9]*) _mw=30 ;; esac
    [ "$_mw" -lt 10 ] && _mw=10
    fa_modewatch_stop
    (
        _last=""
        while true; do
            _t=$(fa_current_aod_type)
            if [ -n "$_t" ] && [ "$_t" != "$_last" ]; then
                if [ -n "$_last" ]; then
                    fa_log "aod type changed $_last -> $_t, re-apply panel string + restart nightpearl"
                    fa_build_fake
                    fa_apply_sysfs
                    killall com.vivo.nightpearl 2>/dev/null
                fi
                _last=$_t
            fi
            sleep "$_mw"
        done
    ) >/dev/null 2>>"$LOG" &
    echo $! > "$WORK/modewatch.pid" 2>/dev/null
    fa_log "modewatch started pid=$(cat "$WORK/modewatch.pid" 2>/dev/null)"
}

fa_recent_log() {
    logcat -d 2>/dev/null | grep -i -E "VivoAod|AodViewMediator|AodMusic|KeyguardUpdateMonitor|DozeService|MediaSession|NightPearl|aod_show|notification" \
        | grep -v -E "CompositionEngine|ConfigStore" | tail -n 60
}

# ---------------- v3.0 亮度守卫 ----------------
GUARD_LOG=$WORK/guard.log
GUARD_PID=$WORK/guard.pid

fa_guard_log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$GUARD_LOG" 2>/dev/null
}

fa_guard_running() {
    _p=$(cat "$GUARD_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_p" -gt 1 ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    return 0
}

fa_guard_stop() {
    _p=$(cat "$GUARD_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) _p="" ;; esac
    if [ -n "$_p" ] && [ "$_p" -gt 1 ]; then
        kill -TERM "$_p" 2>/dev/null
    fi
    # 先杀我们那一个 logcat（命令行里带 power_screen_state:I），触发管道 EOF，循环自然退出；
    # 再清掉可能残留的 guard.sh 进程。只按命令行精确匹配，不动系统里别的 logcat。
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[p]ower_screen_state:I" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[g]uard\.sh" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$GUARD_PID" 2>/dev/null
    fa_guard_log "guard stopped"
}

fa_guard_start() {
    if [ "$(fa_conf BRIGHT_GUARD 1)" != "1" ]; then
        fa_guard_log "BRIGHT_GUARD=0, skip"
        return 0
    fi
    if fa_guard_running; then
        fa_guard_log "guard already running (pid $(cat "$GUARD_PID" 2>/dev/null))"
        return 0
    fi
    mkdir -p "$WORK" 2>/dev/null
    # 清掉可能残留的旧实例（pid 文件丢了的情况），避免“明明没在跑却说已在跑”
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[g]uard\.sh" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$GUARD_PID" 2>/dev/null
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$MODDIR/guard.sh" >>"$GUARD_LOG" 2>&1 &
    else
        ( sh "$MODDIR/guard.sh" >>"$GUARD_LOG" 2>&1 & )
    fi
    sleep 1
    if fa_guard_running; then
        fa_log "guard started (pid $(cat "$GUARD_PID" 2>/dev/null))"
        fa_guard_log "guard started (pid $(cat "$GUARD_PID" 2>/dev/null))"
    else
        fa_log "guard FAILED to start, see $GUARD_LOG"
    fi
}

# ---------------- v3.2 熄屏显示超时（aodkeep） ----------------
AODK_LOG=$WORK/aod.log
AODK_PID=$WORK/aod.pid

fa_aod_running() {
    _p=$(cat "$AODK_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_p" -gt 1 ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    return 0
}

fa_aod_stop() {
    _p=$(cat "$AODK_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) _p="" ;; esac
    [ -n "$_p" ] && kill -KILL "$_p" 2>/dev/null
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[a]odkeep\.sh" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[n]otification_enqueue:I" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$AODK_PID" 2>/dev/null
    echo "$(date '+%m-%d %H:%M:%S') aodkeep stopped" >> "$AODK_LOG" 2>/dev/null
}

fa_aod_start() {
    if [ "$(fa_conf AOD_TIMEOUT 1)" != "1" ]; then
        echo "$(date '+%m-%d %H:%M:%S') AOD_TIMEOUT=0, skip" >> "$AODK_LOG" 2>/dev/null
        return 0
    fi
    if fa_aod_running; then
        fa_log "aodkeep already running (pid $(cat "$AODK_PID" 2>/dev/null))"
        return 0
    fi
    mkdir -p "$WORK" 2>/dev/null
    # 清掉可能残留的旧实例，避免“没在跑却被当成在跑”
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[a]odkeep\.sh" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$AODK_PID" 2>/dev/null
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$MODDIR/aodkeep.sh" >>"$AODK_LOG" 2>&1 &
    else
        ( sh "$MODDIR/aodkeep.sh" >>"$AODK_LOG" 2>&1 & )
    fi
    sleep 1
    if fa_aod_running; then
        fa_log "aodkeep started (pid $(cat "$AODK_PID" 2>/dev/null))"
    else
        fa_log "aodkeep FAILED to start, see $AODK_LOG"
    fi
}

# ---------------- v4.0 传感器桥（app_process） ----------------
SENSOR_STATE=$WORK/sensor.state
SENSOR_CMD=$WORK/sensor.cmd
SENSOR_LOG=$WORK/sensor.log
SENSOR_PID=$WORK/sensor.pid

fa_sensor_running() {
    _p=$(cat "$SENSOR_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_p" -gt 1 ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    return 0
}

fa_sensor_stop() {
    _p=$(cat "$SENSOR_PID" 2>/dev/null)
    case "$_p" in ''|*[!0-9]*) _p="" ;; esac
    [ -n "$_p" ] && [ "$_p" -gt 1 ] && kill -KILL "$_p" 2>/dev/null
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[c]om.dsh.aod.SensorBridge" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$SENSOR_PID" "$SENSOR_CMD" 2>/dev/null
    fa_log "sensor bridge stopped"
}

fa_sensor_start() {
    if [ "$(fa_conf SENSOR_BRIDGE 1)" != "1" ]; then
        fa_log "SENSOR_BRIDGE=0, skip"
        return 0
    fi
    if [ ! -f "$MODDIR/sensor.dex" ]; then
        fa_log "sensor.dex missing, skip bridge"
        return 1
    fi
    if fa_sensor_running; then
        fa_log "sensor bridge already running (pid $(cat "$SENSOR_PID" 2>/dev/null))"
        return 0
    fi
    for _q in $(ps -A -o PID,ARGS 2>/dev/null | grep "[c]om.dsh.aod.SensorBridge" | awk '{print $1}'); do
        case "$_q" in ''|*[!0-9]*) continue ;; esac
        kill -KILL "$_q" 2>/dev/null
    done
    rm -f "$SENSOR_STATE" "$SENSOR_CMD" 2>/dev/null
    if command -v setsid >/dev/null 2>&1; then
        CLASSPATH="$MODDIR/sensor.dex" setsid app_process /system/bin com.dsh.aod.SensorBridge >>"$SENSOR_LOG" 2>&1 &
    else
        ( CLASSPATH="$MODDIR/sensor.dex" app_process /system/bin com.dsh.aod.SensorBridge >>"$SENSOR_LOG" 2>&1 & )
    fi
    echo $! > "$SENSOR_PID" 2>/dev/null
    sleep 2
    if [ -f "$SENSOR_STATE" ]; then
        fa_log "sensor bridge ok: $(cat "$SENSOR_STATE" 2>/dev/null)"
        return 0
    fi
    fa_log "sensor bridge FAILED to start, see $SENSOR_LOG"
    return 1
}

fa_sensor_lux() {
    _l=$(sed -n 's/.*lux=\([0-9-][0-9]*\).*/\1/p' "$SENSOR_STATE" 2>/dev/null)
    case "$_l" in ''|*[!0-9-]*) _l="" ;; esac
    printf '%s' "$_l"
}

fa_sensor_fresh() {
    _ts=$(sed -n 's/.*ts=\([0-9][0-9]*\).*/\1/p' "$SENSOR_STATE" 2>/dev/null)
    case "$_ts" in ''|*[!0-9]*) return 1 ;; esac
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) return 1 ;; esac
    [ $((_now - _ts)) -le 5 ] && return 0
    return 1
}

fa_sensor_sleep() {
    if fa_sensor_running && fa_sensor_fresh; then
        printf 'sleep' > "$SENSOR_CMD" 2>/dev/null
        fa_log "ask sensor bridge to goToSleep"
        return 0
    fi
    return 1
}

# 自动亮度（系统自带的光线传感器方案，0=关 1=开）
fa_apply_auto_bright() {
    ab=$(fa_conf AUTO_BRIGHT 0)
    case "$ab" in
        1) settings put system screen_brightness_mode 1 2>/dev/null ;;
        0) settings put system screen_brightness_mode 0 2>/dev/null ;;
        *) return 0 ;;
    esac
    fa_log "screen_brightness_mode = $(settings get system screen_brightness_mode 2>/dev/null) (AUTO_BRIGHT=$ab)"
}

# 一键把「当前亮度」重新下发一次：先 ±3 级再回到原值，触发系统重新算一次背光
# 用法：fa_brightness_refresh <标签> [1=附带 dumpsys 快照]
fa_brightness_refresh() {
    _tag="$1"
    _dump="${2:-0}"
    _b=$(settings get system screen_brightness 2>/dev/null)
    case "$_b" in ''|*[!0-9]*) _b="" ;; esac
    _f=$(settings get system screen_brightness_float 2>/dev/null)
    case "$_f" in ''|null|*[!0-9.]*) _f="" ;; esac
    _m=$(settings get system screen_brightness_mode 2>/dev/null)

    fa_guard_log "refresh[$_tag] int=$_b float=$_f mode=$_m"
    if [ "$_dump" = "1" ] && [ "$(fa_conf GUARD_DEBUG 1)" = "1" ]; then
        fa_guard_log "  before: $(dumpsys display 2>/dev/null | grep -m2 -E 'mScreenBrightnessSetting|Display Brightness=')"
    fi

    if [ -n "$_b" ]; then
        if [ "$_b" -gt 200 ]; then _nb=$((_b - 3)); else _nb=$((_b + 3)); fi
        settings put system screen_brightness "$_nb" 2>/dev/null
        sleep 0.2
        settings put system screen_brightness "$_b" 2>/dev/null
    fi
    if [ -n "$_f" ]; then
        _nf=$(echo "$_f" | awk '{ v=$1+0; n=(v>0.9)? v-0.008 : v+0.008; printf "%.6f", n }' 2>/dev/null)
        if [ -n "$_nf" ]; then
            settings put system screen_brightness_float "$_nf" 2>/dev/null
            sleep 0.2
            settings put system screen_brightness_float "$_f" 2>/dev/null
        fi
    fi

    if [ "$_dump" = "1" ] && [ "$(fa_conf GUARD_DEBUG 1)" = "1" ]; then
        fa_guard_log "  after : $(dumpsys display 2>/dev/null | grep -m2 -E 'mScreenBrightnessSetting|Display Brightness=')"
    fi
}

