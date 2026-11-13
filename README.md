# Neo9SP_AOD · 为 iQOO Neo9S Pro 开启系统隐藏的全屏熄屏显示

> 熄屏不是落幕，是留给往事的留白。
> 长夜漫过屏幕，微光替我念想。

让 iQOO Neo9S Pro（PD2339 / V2339A）用上 OriginOS 里被隐藏的「全屏息屏显示 / 全天候 AOD」。

**从 v8.0 起只需要一个 KSU 模块，不再需要 LSPosed。**

| 模块 | 作用 | 形态 | 状态 |
|---|---|---|---|
| **Neo9SP_AOD (KSU)** | 开启全屏 AOD、控制 AOD 亮度与超时熄灭、布局写转发 | KernelSU / Magisk 模块 | ✅ 唯一需要安装的模块 |
| ~~Neo9SP_AOD (LSPosed)~~ | 旧版用于「让设置页出现局部/全屏入口」 | LSPosed 模块 | ⛔ v8.x 起已废弃，不要再装 |

> 为什么不再需要 LSPosed：
> 旧版伪造的面板能力串是 `/data` 副本，标签（adb_data_file / vendor_file）不对，
> 夜明珠（system_app）读不到 → `e0()` 恒为 false，只能靠 hook 把返回值顶成 true。
> v8.0 改用 **tmpfs + `context=u:object_r:sysfs_oled_hbm:s0`** 生成假节点，
> 标签与真节点一致，夜明珠自己就能读取，设置页的「局部/全屏」自然出现。

---

## 适配情况

- 机型：iQOO Neo9S Pro（PD2339 / V2339A）
- 系统：OriginOS 6 / `PD2339I_A_16.2.13.1.W10.V000L1`
- 面板：Visionox **RM692H5**
- 前提：KernelSU（或 Magisk），**不需要 LSPosed**

## 安装

1. KernelSU / Magisk 里安装 `Neo9SP_AOD_ksu_v8.x.zip`
2. **重启**（KSU 只在开机执行 `service.sh`，不重启跑的还是旧进程）
3. 打开 KSU 管理器点模块的「执行」，确认报告里有：

```
属性 ro.vivo.keyguard_full_aod.enable = 1
tmpfs overlay ok (context=u:object_r:sysfs_oled_hbm:s0)
forwarder started pid=xxxx
bind mount : 已挂载
当前可见   : aod_brightness=956,support_full_screen=1,...
```

4. 进「设置 → 熄屏显示」，应能看到「局部 / 全屏」切换
5. 如果你之前装过 LSPosed 的 Neo9SP_AOD，**现在可以卸载它**（留着也不会冲突，但没有必要）

## v8.x 更新内容

### v8.0 —— 摆脱 LSPosed
- **假节点改用 tmpfs + `context=`**：挂载时指定 SELinux 标签，
  与真节点 `u:object_r:sysfs_oled_hbm:s0` 一致，不再依赖 chcon（chcon 在 ksu 域经常失败）
- **私有 sysfs 挂载**：另挂一份真 sysfs 到模块目录，用来读真实面板串、也用来写真节点
- **布局写转发**：夜明珠会把 AOD 布局坐标（`<i> <j> <x> <y> <w> <h>`，
  来自 `ScreenOffClockView` / `ScreenOffChargingRemindView`）写进这个节点；
  以前这些写被假节点吞掉，导致 AOD 内容偏左、不居中。现在转发给真节点后再还原假串。

### v8.1 —— 修「改定时显示后出错」
- 去掉「局部 → `support_full_screen=0`」的耦合（改定时页后选择器会消失）
- 写回假串前先截断（否则 App 写的短坐标会在文件尾部留残留字节，夜明珠读到混合内容，设置页闪退）
- 转发加白名单：只转发「纯数字 + 空格」的坐标，带 `=` 的一律不写真节点

### v8.2 —— 功耗
- 布局转发器改自适应轮询：有变化时 0.3 秒，连续 5 次无变化后 2 秒
- 默认关闭传感器桥（它每秒写盘 + 常开光线/加速度，是主要耗电源）
- 默认关闭调试日志、关闭 AOD 类型轮询
- AOD 阶梯改为 3 分钟熄灭

## 配置（`/data/adb/iqoo_pd2339_fullaod/config.ini`）

| 键 | 默认 | 说明 |
|---|---|---|
| `SUPPORT_FULL_SCREEN` | `1` | 面板串里的 `support_full_screen` |
| `SYSFS_MODE` | `tmpfs` | `tmpfs`=推荐；`auto`/`mount`=旧方案；`write`=直写 |
| `FWD_LAYOUT` | `1` | 布局写转发（关掉会导致 AOD 内容偏左） |
| `AOD_FIX_LEVEL` | `0` | >0 固定 AOD 亮度；0 = 走阶梯 |
| `AOD_STEPS` | `60:70,180:1` | 60 秒→70%，180 秒熄灭 |
| `AOD_LIGHT_SKIP` | `1000` | 超过该 lux 视为有光（仅传感器桥开启时有效） |
| `SENSOR_BRIDGE` | `0` | 1=启用光线/运动传感器（更费电） |
| `AOD_NOTIFY_RESET` | `1` | 来消息是否重置变暗计时 |
| `AOD_DEBUG` | `0` | 1=每个事件都写日志（调试用，费电） |
| `SMART_AOD` | `0` | 必须 0，否则静止后 AOD 画面冻结（时钟不走） |
| `DISABLE` | `0` | 1=整体停用，当场退回原厂 |

改完保存 → 点「执行」即时生效，不需要重启。

## 已知问题

1. **秒表 / 倒计时 / 音乐进度的数字**在 AOD 上不显示（显示 `01:--`）。
   本机面板 Visionox RM692H5 的 dbi 初始化码编在内核 LCM 驱动里，不在 `/vendor/etc`；
   `support_video_aod=1` 只会引入渲染 bug，不会显示数字。属于面板能力边界。
2. **熄屏瞬间轻微闪烁**：固件 `doze → doze_suspend` 硬切行为。
3. 局部/全屏切换属于系统自身能力，模块只负责让夜明珠读到面板能力；
   切换后若布局没刷新，等系统重绘或锁屏一次。

## 卸载 / 回滚

- 临时停用：`DISABLE=1` + 点「执行」，当场恢复原厂
- 彻底卸载：KSU 管理器卸载模块 → 重启
  - 卸载脚本会：停守护进程、还原/清理 settings、循环 umount（含 tmpfs 与私有 sysfs）、重启夜明珠
  - 另存 `/data/local/tmp/aod_clean.sh`：模块被「直接删除」时可手动执行清理，不用重启
- **不改写任何分区**：所有改动都是运行时挂载 / 属性 / settings，重启即恢复

## 旧版本升级说明

- 从 v7.x 或更早升级：直接覆盖安装 v8.2 并重启
  - `SYSFS_MODE` 会被迁移成 `tmpfs`
  - 旧的 LSPosed 模块可以卸载
- 如果升级后设置页仍闪退，执行一次清理脚本再重启：
  ```sh
  su -c "sh /data/local/tmp/aod_clean.sh"
  ```

## 开源

- License: **MIT**
- 作者：酷安 @小雨爱分享
- 历史版本与踩坑记录见 `README-HISTORY.md`（旧版逐版复盘）

## 致谢

- 酷安 @小雨爱分享 —— 原始「全屏 AOD」思路与模块骨架
- X100s 全屏 AOD 模块（Hao_o0o）—— tmpfs + context 假节点、布局写转发、亮度跟随器的思路参考
- KernelSU / LSPosed 社区
