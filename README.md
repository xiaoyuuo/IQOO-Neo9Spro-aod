# Neo9SP_AOD · 为 iQOO Neo9S Pro 开启系统隐藏的全屏熄屏显示

> 熄屏不是落幕，是留给往事的留白。
> 长夜漫过屏幕，微光替我念想。

让 iQOO Neo9S Pro（PD2339 / V2339A）用上 OriginOS 里被隐藏的「全屏息屏显示 / 全天候 AOD」。

本仓库包含 **两个必须配套使用的模块**：

| 模块 | 作用 | 形态 |
|---|---|---|
| **Neo9SP_AOD (KSU)** | 开启全屏 AOD、控制 AOD 亮度与超时熄灭 | KernelSU / Magisk 模块 |
| **Neo9SP_AOD (LSPosed)** | 让设置页出现「局部 / 全屏」入口，并让熄屏显示按全屏渲染 | LSPosed 模块 |

> KSU 模块负责“能不能显示”，LSPosed 模块负责“设置里能不能选”。
> 只装 KSU：效果可用，但设置页没有切换入口。
> 只装 LSPosed：没有属性与面板能力串，全屏 AOD 起不来。

---

## 适配情况

- 机型：iQOO Neo9S Pro（PD2339 / V2339A）
- 系统：OriginOS 6 / `PD2339I_A_16.2.13.1.W10.V000L1`
- 面板：Visionox **RM692H5**（`pd2339_panel_visionox_rm692h5_cmd`）
- 前提：KernelSU（或 Magisk + Zygisk）+ LSPosed

## 目录结构

```
.
├─ ksu/                     KSU 模块源码（脚本 + config.ini + module.prop）
│  ├─ module.prop
│  ├─ post-fs-data.sh
│  ├─ service.sh
│  ├─ action.sh
│  ├─ common.sh
│  ├─ aodkeep.sh
│  ├─ sepolicy.rule
│  ├─ config.ini
│  └─ README.md             版本演进与踩坑记录
├─ lsposed/                 LSPosed 模块源码
│  ├─ Main.java
│  ├─ AndroidManifest.xml
│  ├─ res/values/arrays.xml 作用域：只有 com.vivo.nightpearl
│  ├─ assets/xposed_init
│  ├─ build.ps1             aapt2 + javac + d8 + zipalign + apksigner
│  └─ LICENSE
├─ release/                 发布用成品
└─ README.md
```

## 安装

1. **KSU 模块**：KernelSU / Magisk 里安装 `Neo9SP_AOD_ksu_*.zip` → 重启
2. **LSPosed 模块**：安装 `Neo9SP_AOD_lsposed_*.apk` → 在 LSPosed 里启用
   - 作用域只需要勾选 **「熄屏显示」**（`com.vivo.nightpearl`）
3. 打开 KSU 管理器，点模块的「执行」（Action），确认报告里：
   ```
   属性 ro.vivo.keyguard_full_aod.enable = 1
   bind mount : 已挂载
   当前可见   : ...support_full_screen=1...
   ```

## 配置（`/data/adb/iqoo_pd2339_fullaod/config.ini`）

| 键 | 默认 | 说明 |
|---|---|---|
| `SUPPORT_FULL_SCREEN` | `1` | 面板串里的 `support_full_screen` |
| `MOUNT_SYSFS` | `1` | 是否伪造面板能力串 |
| `SYSFS_MODE` | `auto` | `auto`=先直写真节点，失败再 bind mount |
| `AOD_FIX_LEVEL` | `0` | >0 固定 AOD 亮度（956≈原厂），0 = 走阶梯 |
| `AOD_STEPS` | `15:85,60:70,300:1` | 15s→85%、60s→70%、300s 熄灭 |
| `AOD_OFF_LEVEL` | `1` | 熄灭档（1≈全黑） |
| `AOD_LIGHT_SKIP` | `1000` | 超过该 lux 视为有光，不压暗不熄灭 |
| `AOD_TYPE` | `2` | 1=局部 2=融合 3=全屏 |
| `SENSOR_BRIDGE` | `1` | 启用传感器桥（到点真熄屏） |
| `DISABLE` | `0` | 1 = 整体停用，当场退回原厂 |

改完保存 → 点「执行」即时生效，不需要重启。

## 已知问题

1. **秒表 / 倒计时 / 音乐进度的数字在 AOD 上不显示**（显示 `01:--`）。
   RM692H5 的面板初始化码（dbi）编在内核 LCM 驱动里，不在 `/vendor/etc`；
   `support_video_aod=1` 只会引入渲染 bug，不会显示数字。属于面板/固件能力边界。
2. **熄屏瞬间轻微闪烁**：固件 `doze → doze_suspend` 硬切，切换那一帧按寄存器值显示。
3. **设置页「局部/全屏」入口**：需要 LSPosed 模块；本机补丁 APK 装不上（-911）、
   bind mount 也不可用。
4. 切到「局部」后布局偶尔不重排：等待自动联动，或手动点一次「执行」。

## 卸载 / 回滚

- 临时停用：`DISABLE=1` + 点「执行」→ 当场恢复原厂
- 彻底卸载：KSU 管理器卸载 + 重启；`/data/adb/iqoo_pd2339_fullaod/` 可手动删除
- 本模块**不改写任何分区**：所有改动都是运行时 bind mount / 属性 / settings，重启即恢复

## 开源

- License: **MIT**（见 `LICENSE`）
- 作者：酷安 @小雨爱分享
- LSPosed 模块的 `Main.java` 为可读源码，`build.ps1` 可一键构建

## 致谢

- 酷安 @小雨爱分享 —— 原始「全屏 AOD」思路与模块骨架
- KernelSU / LSPosed 社区
