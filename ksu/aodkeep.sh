#!/system/bin/sh
# 熄屏显示超时守护 v3.7
#
# 目标：全屏熄屏显示里，长时间没有“真消息”就一级级变暗，最后直接熄掉：
#   15 秒 → 85%，60 秒 → 70%，300 秒 → 黑掉（user=AOD_OFF_LEVEL）
#   来真消息 → 恢复原亮度并重新计时
#   亮屏/解锁 → 立即撤销并恢复
#
# v3.7 的关键改动：状态只认 power_screen_state 的 displayState（第二个字段）。
# 这台机器在进出 AOD 时会连发好几组 screen_toggled 0/1（doze 与 doze_suspend 切换），
# v3.6 用 screen_toggled=1 当“亮屏”去撤销+恢复，结果 AOD 刚一进就被自己撤销，
# 表现为“完全没有变暗”。现在 screen_toggled 只用于日志，不再驱动状态机。
#
# 另外每次进入 AOD 先把亮度写回原厂 956，再开始阶梯，
# 这样不会继承上一轮残留的暗值（避免“一熄屏 1~2 秒就超级暗”）。
#
# 控制点 /sys/lcm/aod_bl_level，内容是 "user=956,current=0" 键值串，按 user= 写。

MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
AOD_LOG=$WORK/aod.log
AOD_PID=$WORK/aod.pid
AOD_MARK=$WORK/aod_off_fired

echo $$ > "$AOD_PID" 2>/dev/null

aod_log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$AOD_LOG" 2>/dev/null
}

if [ "$(fa_conf AOD_TIMEOUT 1)" != "1" ]; then
    aod_log "AOD_TIMEOUT=0, exit"
    rm -f "$AOD_PID"
    exit 0
fi

STEPS=$(fa_conf AOD_STEPS "15:85,60:70,300:1")
OFF_LEVEL=$(fa_conf AOD_OFF_LEVEL 1)
case "$OFF_LEVEL" in ''|*[!0-9]*) OFF_LEVEL=1 ;; esac
AOD_DEBUG=$(fa_conf AOD_DEBUG 0)
NOTIFY_RESET=$(fa_conf AOD_NOTIFY_RESET 0)
LIGHT_SKIP=$(fa_conf AOD_LIGHT_SKIP 1000)
case "$LIGHT_SKIP" in ''|*[!0-9]*) LIGHT_SKIP=1000 ;; esac
# v5.2：固定 AOD 亮度。>0 时不跑阶梯，进 AOD 就把 aod_bl_level 写成这个值，
# 亮屏再恢复。因为面板串里的 aod_brightness 对全屏 AOD 无效（956 和 4000 都是最暗），
# aod_bl_level 才是真正管 AOD 亮度的节点。
FIX_LEVEL=$(fa_conf AOD_FIX_LEVEL 956)
case "$FIX_LEVEL" in ''|*[!0-9]*) FIX_LEVEL=0 ;; esac

aod_level_read() {
    cat "$AOD_BL" 2>/dev/null | tr -d '\r\n'
}

aod_level_user() {
    _s=$(aod_level_read)
    _u=$(printf '%s' "$_s" | sed -n 's/.*user=\([0-9][0-9]*\).*/\1/p')
    case "$_u" in ''|*[!0-9]*) _u="" ;; esac
    printf '%s' "$_u"
}

# v4.3 实测：/sys/lcm/aod_bl_level 只接受裸数字；
# `user=956` / `user=956,current=956` / `echo` 全部 EINVAL，只有 printf '956' 成功。
aod_level_write() {
    _v="$1"
    # v7.7：v6.2 这里退化成 echo，带换行会被节点拒绝（Neo7 日志里全是 set ... FAILED）。
    # 先按实测唯一可靠的写法 printf '%s'（不带换行），再校验。
    printf '%s' "$_v" > "$AOD_BL" 2>>"$AOD_LOG"
    _rc=$?
    _rb=$(aod_level_read)
    aod_log "  set $_v (printf rc=$_rc) -> node='$_rb'"
    case "$_rb" in
        *"user=$_v"*) return 0 ;;
        "$_v"*) return 0 ;;
    esac
    echo "$_v" > "$AOD_BL" 2>>"$AOD_LOG"
    _rb=$(aod_level_read)
    aod_log "  retry echo -> node='$_rb'"
    case "$_rb" in
        *"user=$_v"*|"$_v"*) return 0 ;;
    esac
    echo "user=$_v,current=$_v" > "$AOD_BL" 2>>"$AOD_LOG"
    _rb=$(aod_level_read)
    aod_log "  retry user=,current= -> node='$_rb'"
    case "$_rb" in
        *"user=$_v"*) return 0 ;;
    esac
    aod_log "  set $_v FAILED, node=$(aod_level_read)"
    return 1
}

# 基准亮度：优先面板串里的 aod_brightness（原厂 956）
aod_base_level() {
    _b=$(sed -n 's/.*aod_brightness=\([0-9][0-9]*\).*/\1/p' "$SYSFS" 2>/dev/null)
    case "$_b" in ''|*[!0-9]*) _b="" ;; esac
    if [ -z "$_b" ]; then
        _b=$(aod_level_user)
        case "$_b" in ''|*[!0-9]*|0) _b=956 ;; esac
    fi
    printf '%s' "$_b"
}

TIMER_PID=""
DOZING=0
BASE=956

cancel_timer() {
    [ -n "$TIMER_PID" ] && kill -KILL "$TIMER_PID" 2>/dev/null
    TIMER_PID=""
}

start_timer() {
    cancel_timer
    rm -f "$AOD_MARK" 2>/dev/null
    aod_log "timer start: base=$BASE steps=$STEPS"
    (
        _prev=0
        _oldifs=$IFS
        IFS=','
        for _step in $STEPS; do
            _t=${_step%%:*}
            _pct=${_step#*:}
            case "$_t" in ''|*[!0-9]*) continue ;; esac
            case "$_pct" in ''|*[!0-9]*) continue ;; esac
            _gap=$((_t - _prev))
            [ "$_gap" -gt 0 ] && sleep "$_gap"
            _prev=$_t
            # 有光（手电筒/室外）就不压亮度、也不熄屏
            _lx=""
            if fa_sensor_fresh; then
                _lx=$(fa_sensor_lux)
                case "$_lx" in ''|*[!0-9]*) _lx="" ;; esac
            fi
            if [ -n "$_lx" ] && [ "$_lx" -ge "$LIGHT_SKIP" ]; then
                aod_log "  step ${_t}s: bright (lux=$_lx >= $LIGHT_SKIP), skip"
                continue
            fi
            if [ "$_pct" -le 1 ]; then
                aod_log "  step ${_t}s -> OFF"
                if fa_sensor_sleep; then
                    aod_log "  goToSleep sent to sensor bridge"
                    sleep 1
                fi
                aod_level_write "$OFF_LEVEL"
                : > "$AOD_MARK" 2>/dev/null
            else
                _lvl=$((BASE * _pct / 100))
                [ "$_lvl" -lt 1 ] && _lvl=1
                aod_log "  step ${_t}s -> ${_pct}% (level $_lvl)"
                aod_level_write "$_lvl"
            fi
        done
        IFS=$_oldifs
    ) &
    TIMER_PID=$!
}

on_doze() {
    [ "$DOZING" = "1" ] && return 0
    DOZING=1
    BASE=$(aod_base_level)
    aod_log "AOD enter (base=$BASE fix=$FIX_LEVEL)"
    if [ "$FIX_LEVEL" -gt 0 ]; then
        # 固定亮度模式：不跑阶梯，直接给 AOD 一个固定档位
        aod_log "  fix level -> $FIX_LEVEL"
        aod_level_write "$FIX_LEVEL"
        return 0
    fi
    # 先归位再加阶梯，避免继承上一轮的暗值
    aod_level_write "$BASE"
    start_timer
}

on_wake() {
    [ "$DOZING" = "0" ] && return 0
    DOZING=0
    cancel_timer
    rm -f "$AOD_MARK" 2>/dev/null
    aod_log "wake/unlock: restore $BASE"
    aod_level_write "$BASE"
    # 让传感器桥再补一次：写两次 956 + 让系统重新下发一次正常亮度
    # （不然解锁后桌面会停留在这个很低的 AOD 档位）
    printf 'restore' > "$SENSOR_CMD" 2>/dev/null
}

# 音乐小部件/播放器会几秒一次重发通知事件，必须排除
is_noise_notify() {
    case "$1" in
        *musicwidget*|*MusicWidget*|*VivoMusicWidgetMix*|*PLAY_SERVICE*|*player_service*|*groupKey=player*) return 0 ;;
    esac
    return 1
}

_last_notify=0

on_notify() {
    [ "$DOZING" = "1" ] || return 0
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
    # 5 秒内的连发通知只算一次，避免 QQ/微信 连续几条把阶梯无限重置
    if [ "$_now" -gt 0 ] && [ "$_last_notify" -gt 0 ] && [ $((_now - _last_notify)) -lt 5 ]; then
        aod_log "notify debounced"
        return 0
    fi
    _last_notify=$_now
    if [ "$FIX_LEVEL" -gt 0 ]; then
        aod_log "notification -> keep fix level $FIX_LEVEL"
        aod_level_write "$FIX_LEVEL"
        return 0
    fi
    aod_log "real notification -> restore $BASE and retimer"
    aod_level_write "$BASE"
    rm -f "$AOD_MARK" 2>/dev/null
    start_timer
}

# power_screen_state 的 displayState 是第二个字段：2=ON，3=DOZE，4=DOZE_SUSPEND
aod_display_state() {
    printf '%s' "$1" | sed -n 's/.*\[[0-9]*,\([0-9]*\).*/\1/p'
}

aod_log "==== aodkeep v5.7 start (pid $$) ===="
aod_log "node=$AOD_BL exists=$([ -e "$AOD_BL" ] && echo yes || echo no) steps=$STEPS off_level=$OFF_LEVEL"
aod_log "node now: $(aod_level_read)"

if fa_pick_aod_bl; then
    aod_log "aod_bl node -> $AOD_BL"
else
    aod_log "aod_bl node probe failed, fallback $AOD_BL"
fi
BASE=$(aod_base_level)
aod_log "startup restore base=$BASE"
aod_level_write "$BASE"

_round=0
_fail=0
while :; do
    _round=$((_round + 1))
    aod_log "watching events (round $_round)"
    # v7.1 功耗：默认不订阅通知（QQ/微信的通知洪流会让 shell 每秒解析十几行），
    # 需要“来消息重置计时”再把 AOD_NOTIFY_RESET 改成 1。
    if [ "$NOTIFY_RESET" = "1" ]; then
        _TAGS="power_screen_state screen_toggled notification_enqueue"
    else
        _TAGS="power_screen_state screen_toggled"
    fi
    logcat -b events -v brief -s $_TAGS 2>/dev/null \
    | while IFS= read -r line; do
        case "$line" in
            *power_screen_state*)
                _ds=$(aod_display_state "$line")
                [ "$AOD_DEBUG" = "1" ] && aod_log "ev: displayState=$_ds"
                case "$_ds" in
                    2) on_wake ;;
                    3|4) on_doze ;;
                esac
                ;;
            *screen_toggled*)
                # 只记日志，不驱动状态机（进出 AOD 时会连发 0/1，驱动它会把计时器撤销掉）
                [ "$AOD_DEBUG" = "1" ] && aod_log "ev: screen_toggled(ignored)"
                ;;
            *notification_enqueue*)
                if is_noise_notify "$line"; then
                    :
                else
                    [ "$AOD_DEBUG" = "1" ] && aod_log "ev: notify $(printf '%s' "$line" | cut -c1-50)"
                    on_notify
                fi
                ;;
        esac
    done
    _fail=$((_fail + 1))
    aod_log "logcat exited, restart in 3s (fail=$_fail)"
    [ "$_fail" -gt 20 ] && break
    sleep 3
done

rm -f "$AOD_PID" 2>/dev/null
aod_log "aodkeep exit"
