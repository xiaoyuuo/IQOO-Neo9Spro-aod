# 已知 Bug

> 环境：iQOO Neo9S Pro（PD2339）/ OriginOS 6 / `PD2339I_A_16.2.13.1.W10.V000L1`
> 熄屏显示 `com.vivo.nightpearl` 8.0.4.2 / KernelSU + LSPosed / 配置 `AOD_TYPE=2`
>
> **使用前提：熄屏显示 → 更多熄屏设置 → 显示方式 必须选「全天显示」。**
> 选「轻移手机显示 / 定时显示」时，静止或到时间后 AOD 会整块熄灭，看起来就像"又开始黑屏了"。

| # | 现象 | 解决方法 |
|---|---|---|
| 1 | 切换回局部熄屏，再切回全屏后，实时显示失效 | 在 KSU 管理器里点一下模块的「执行 / Action」（重写 AOD 类型配置） |
| 2 | 会先黑一下屏再亮屏，亮屏时会闪一下（实时显示的情况下） | 暂无 |
| 3 | 目前只有时间和消息通知实时显示 | 暂无 |

---

## Bug 1：切换类型后实时刷新失效

**复现**

1. 全屏熄屏正常实时刷新；
2. 把 AOD 类型切回「局部熄屏」；
3. 再切回「全屏熄屏」→ 画面正常，但时间、通知都不再刷新。

**原因**

类型写入 `vivo_keyguard_aod_type` 后，熄屏显示进程只在启动时读取一次；来回切换时写回的类型可能是旧值。

**临时解决**

在 KSU 管理器里点一下模块的「执行 / Action」，会重新写入 `AOD_TYPE=2` 并重启相关进程。

---

## Bug 2：进入 AOD 会先黑一下，亮屏会闪一下

**现象**

熄屏后先短暂黑屏，再出现 AOD；亮屏瞬间也会闪一下。

**已排除的方向**（供后来者少走弯路）

- 不是 CPU 挂起：熄屏期间持有 `PARTIAL_WAKE_LOCK` 仍然不刷新；
- 不是 SystemUI 的判定：去掉对 `VivoAodViewMediator.isFullAodType()` 的强制后依旧；
- 不是伪造面板串：`MOUNT_SYSFS=0`（只写属性，等价 Neo10 模块）依旧；
- 不是 App 动画：把 `MSG_START_KEYGUARD_TO_AOD_ANIMATION` 消息吞掉（`k5.a$c.handleMessage`，`what == 0`）依旧黑。

**实测数据**

录屏 720×1280 @30fps，逐帧看：

```
帧 1–2   锁屏（亮）
帧 3–6   亮度下降、画面变暗
帧 7–9   全黑（约 0.75–1.0 秒）
帧 10+    AOD 淡入
```

**判断**

属于显示栈从「亮屏」切「AOD」时的一次背光关闭/重开（off → doze 的时序），不在应用层。
可疑点：如果「熄屏显示」进程是冷的（比如刚点完 Action 被重启过），首次进 AOD 要等它起来，黑的时间会更长。

---

## Bug 3：只有时间和通知实时刷新

**现象**

时间、通知会刷新；音乐播放进度、部分第三方通知内容不刷新。

**线索**

- AOD 音乐卡片由熄屏显示自己的 `AodMusicManager` 维护（消息 `MSG_UPDATE_AOD_MUSIC`），内置适配 `com.android.bbkmusic`、`com.luna.music`；第三方播放器通常只能拿到歌名；
- 手机静止时 AOD 会暂停刷新、拿起或倾斜才恢复——这是 vivo 的智能熄屏策略，原厂局部 AOD 同样如此。可尝试 `config.ini` 里 `SMART_AOD=0`，或关闭「更多熄屏设置 → 智能显示」。

---

## 欢迎各位大牛来修 bug 😍

提交前建议附上：

- 机型 / 固件版本 / 熄屏显示版本；
- KSU 模块「执行 / Action」的完整输出；
- `logcat` 中 `VivoAod`、`AodViewMediator`、`AodMusic`、`KeyguardUpdateMonitor` 相关日志。

PR 直接改 `ksu/` 或 `lsp/` 下的源码即可，构建方式见 [README](../README.md#构建进阶)。
