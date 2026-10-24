#!/system/bin/sh
# 卸载：撤掉 bind mount（含熄屏显示 APK），清工作目录与日志
SYSFS=/sys/lcm/aod_disp_info
MODID=iqoo_pd2339_fullaod

if grep -q " $SYSFS " /proc/mounts 2>/dev/null; then
    umount "$SYSFS" 2>/dev/null
fi

base=$(pm path com.vivo.nightpearl 2>/dev/null | sed 's/package://' | grep -m1 'base.apk')
if [ -n "$base" ] && grep -q " $base " /proc/mounts 2>/dev/null; then
    umount "$base" 2>/dev/null
fi

rm -rf "/data/adb/${MODID}" 2>/dev/null
rm -f "/data/adb/${MODID}.log" 2>/dev/null
