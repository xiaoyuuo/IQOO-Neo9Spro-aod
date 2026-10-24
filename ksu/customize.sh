#!/system/bin/sh
# 安装时：机型检查 + 权限
MODEL=$(getprop ro.vivo.product.model)
MARKET=$(getprop ro.vivo.market.name)
VER=$(getprop ro.vivo.product.version)

ui_print "*********************************************"
ui_print " Neo9SP_aod  v2.1"
ui_print " 机型    : $MODEL / $MARKET"
ui_print " 版本    : $VER"
ui_print " 做法    : resetprop 写全屏AOD开关属性"
ui_print "           + bind mount 面板能力文件（chcon 对齐标签）"
ui_print "           需配合 LSPosed 模块「Neo9SP_aod」一起使用"
ui_print "*********************************************"

case "$MODEL" in
    PD2339*|V2338*)
        ui_print "- 机型匹配 (Neo9S Pro)，继续安装"
        ;;
    "")
        ui_print "- 读不到机型属性，仍继续安装（不匹配也只影响生效）"
        ;;
    *)
        ui_print "- 警告：机型 $MODEL 不是 PD2339 / V2338A 系列"
        ui_print "- 仍然安装，但请自行确认 /sys/lcm/aod_disp_info 存在"
        ;;
esac

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
