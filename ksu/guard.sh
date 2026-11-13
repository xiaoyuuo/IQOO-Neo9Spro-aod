#!/system/bin/sh
# 亮度守卫 v3.0
#
# 背景：全屏熄屏显示（AOD）退出后，系统有时不会把「你设置的亮度」重新下发一次，
#       结果屏还停在熄屏显示那一档（比最低亮度亮一点），而控制中心滑块仍显示最低；
#       手动拖一下滑块就恢复了。这里用一个常驻脚本监听「屏幕点亮」事件，
#       点亮后自动帮你做那一次「拖动」——把当前亮度重新下发，肉眼看不出来。
#
# 触发源是 event log 里的 power_screen_state / screen_toggled，事件驱动，不轮询，
# 熄屏待机时不会把 CPU 叫醒。

MODDIR=${0%/*}
. "$MODDIR/common.sh"

mkdir -p "$WORK" 2>/dev/null
echo $$ > "$GUARD_PID" 2>/dev/null

fa_guard_log "==== guard v3.0 start (pid $$) ===="

# 亮屏后 0.8s / 2.5s / 5s 各刷新一次：
# 熄屏显示 → 锁屏 → 解锁这个过程里，系统的亮度恢复时机不固定，多打两次更稳。
guard_on_wake() {
    _why="$1"
    fa_guard_log "WAKE ($_why)"
    (
        sleep 0.8
        fa_brightness_refresh "t0.8" 1
        sleep 1.7
        fa_brightness_refresh "t2.5" 0
        sleep 2.5
        fa_brightness_refresh "t5.0" 0
    ) &
}

_round=0
_fail=0
while :; do
    _round=$((_round + 1))
    fa_guard_log "watching events (round $_round)"
    logcat -b events -v brief power_screen_state:I screen_toggled:I '*:S' 2>/dev/null | while IFS= read -r line; do
        [ "$(fa_conf GUARD_DEBUG 1)" = "1" ] && fa_guard_log "ev: $line"
        case "$line" in
            *power_screen_state*"[2,"*) guard_on_wake "power_screen_state=[2,..]" ;;
            *power_screen_state*"[2]"*) guard_on_wake "power_screen_state=[2]" ;;
            *screen_toggled*": 1") guard_on_wake "screen_toggled=1" ;;
            *screen_toggled*" 1") guard_on_wake "screen_toggled 1" ;;
        esac
    done
    _fail=$((_fail + 1))
    fa_guard_log "logcat exited, restart in 3s (fail=$_fail)"
    if [ "$_fail" -gt 20 ]; then
        fa_guard_log "logcat keeps dying, give up"
        break
    fi
    sleep 3
done

rm -f "$GUARD_PID" 2>/dev/null
fa_guard_log "guard exit"
