# Neo9SP_aod（KSU 模块 v2.1 · 配合 LSPosed 模块「Neo9SP_aod」使用）

目标：只靠 KernelSU 一个模块，让系统自己相信「这台机器支持全屏 AOD」。

## 原理（两件事，都在 zygote 之前）

1. **属性**：`resetprop ro.vivo.keyguard_full_aod.enable 1`
   （外加镜像机器上其它名字像 aod 开关的属性；数值型 time/brightness/fps 跳过）

2. **面板能力文件**：把 `/sys/lcm/aod_disp_info` bind mount 成一个副本，
   内容 = 原文把 `support_full_screen=0` 换成 `1`。
   你机器的原文：`aod_brightness=956,support_full_screen=0,support_1hz=2,support_video_aod=0,doze_suspend_fps=1`

## 版本演进（踩过的坑都在这）

| 版本 | 问题 |
|---|---|
| v1.0 | 只挂载、没管 SELinux 标签 → App 读不到 → AOD 只剩指纹 |
| v1.1 | 去掉挂载，只写属性 → 面板串还是 0，功能不完整 |
| v1.2 | 补了 chcon，但字符串替换用了 `sed` 且没有自检 → 假文件内容其实是原文（`support_full_screen=0`），静默失败 |
| **v1.3** | 纯 shell 替换 + **建完自检**（不含 `support_full_screen=1/2/3` 就写合成串）+ 原标签挂载前采集 + Action 强制重挂 |

## 安装

KSU 管理器 → 模块 → 从本地安装 → 选 zip → **完整重启**。

## 验证（重点）

管理器里点「执行 / Action」，报告里这三条必须成立：

```
bind mount : 已挂载
挂载行     : ... /sys/lcm/aod_disp_info ...
当前可见   : aod_brightness=956,support_full_screen=1,...    ← 必须是 1
原始标签   : u:object_r:xxxx:s0
假文件标签 : u:object_r:xxxx:s0                              ← 必须和原始标签一样
SELinux 拒绝记录（应为空）:
```

Action 会强制重挂一次（umount → 重建 → mount → 杀掉熄屏显示进程让它重新读），
所以点完不用重启就能看效果：

熄屏显示 → 应重新出现「熄屏类型：局部熄屏 / 全屏熄屏」；选全屏熄屏 → 熄屏看过渡。

## 失败时的表现（都是安全的）

- `chcon` 失败 → 模块**不挂载**，系统保持「只有局部熄屏」，不会把 AOD 弄挂；
- `挂载行` 为空 → mount 没成功，报告日志尾部会有原因；
- 此时把 Action 报告发回即可，不需要折腾任何设置。

## 卸载 / 回滚

管理器删除模块 → 重启（`uninstall.sh` 会先 umount 再清目录与日志）。
属性只在内存、mount 重启即消失，无残留。

## 文件

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块信息 |
| `common.sh` | 公共库：resetprop、属性镜像、标签采集、字符串修补、自检、bind mount、AVC 检查 |
| `post-fs-data.sh` | 开机最早：写属性 + 挂载 |
| `service.sh` | 开机末尾复核，晚挂载时重启相关进程 |
| `action.sh` | 「执行」按钮：强制重挂 + 完整诊断报告 |
| `uninstall.sh` | 卸载：umount + 清理 |
| `customize.sh` | 安装时机型检查、权限 |
| `README.md` | 本说明 |

## v1.4 新增：可调面板串 + 开关

配置文件：`/data/adb/iqoo_pd2339_fullaod/config.ini`

```
SUPPORT_FULL_SCREEN=1   # 1/2/3 三档，内部走的亮度与过渡分支不同
AOD_BRIGHTNESS=         # 留空保持原值(956)；可填 900 / 1023 试亮度
DISABLE=0               # 设 1 = 关掉全屏、退回局部熄屏（等于「类型选择器」的手动替代）
```

改完在 KSU 管理器点「执行 / Action」**立刻生效**，不用重启。
Action 还会 dump 一段「近期 AOD / 亮度日志」，用来定位「先最暗再亮一点」。

## 关于设置里的「熄屏类型」选择器

它被 `r4.h.f0()` 的机型白名单挡着：`modelNumber >= 2436 && n && x`，
`PD2339 → 2339` 天生不达标。纯 KSU 改不到 Java 判断，所以这部分由 LSPosed 模块「Neo9SP_aod」负责；
想切回局部熄屏就用上面 `DISABLE=1`。
## v1.5：把「熄屏显示」App 的白名单就地改掉（关键一步）

设置里的「局部熄屏 / 全屏熄屏」选择器受 `r4.h.f0()` 控制：

```
f0() = modelNumber >= 2436 && n && x
```

`PD2339 → 2339`，天生不达标；`e0()/Q()` 也各有门禁。这些是 Java 判断，KSU 改不到，
所以 v1.0~v1.4 怎么调面板串，选择器都不会回来。

v1.5 换个做法：**直接把 App 自己的判断改掉**。

- 取原版 `com.vivo.nightpearl` 的 `classes.dex`，把 `r4.h` 里 `Q()`、`e0()`、`f0()`
  三个方法的方法体就地改成 `const/4 v0,#1; return v0;`（指令数不变，多余补 nop），
  重算 dex 的 SHA1 与 Adler32，打包成 `nightpearl_patched.apk`；
- 开机在 `service.sh` 里（等 `sys.boot_completed=1`，即 PackageManager 已经扫过原包之后）
  用 bind mount 把补丁包顶到 `/data/app/.../com.vivo.nightpearl-xxx/base.apk`；
- 挂之前同样 `chcon` 成原 APK 的标签，避免被 SELinux 拒绝；
- 只在版本等于 **8.0.4.2** 时生效，App 更新后自动跳过（需重新出补丁）。

### 风险与回滚

这是改应用本体，属于本模块里风险最高的一步：

- 万一补丁包损坏导致 App 起不来 → AOD 不可用（手机其余功能正常）；
- 回滚：把 `config.ini` 里 `PATCH_APK=1` 改成 `0`，点一次 Action；或直接删模块重启；
- 卸载脚本会自动 umount 掉这个 APK。
## v1.6 修复

1. **补丁没挂上**：v1.5 里用 `pm path` 找 base.apk，但在模块脚本环境里 `pm` 取不到输出（报
   `com.vivo.nightpearl base.apk not found`）。v1.6 改成从 `dumpsys package` 里的
   `codePath=` 取，稳。
2. **SELinux 拒绝**：Action 里抓到了 `avc: denied { getattr } ... path="/sys/lcm/aod_disp_info"
   tcontext=u:object_r:adb_data_file:s0 app=com.vivo.systemuiplugin` —— 说明 SystemUI 插件读
   我们的假面板文件被拒了（这会直接影响全屏 AOD 的亮度/过渡判断）。v1.6 增加了
   `sepolicy.rule`，放行 platform_app / untrusted_app 读 adb_data_file。
## v1.7：模块和小补丁包分开（解决「装不上 / -911」）

v1.5 / v1.6 把 41MB 的补丁 APK 塞进了模块 zip（约 37MB），某些管理器/安装器会直接拒绝
（你遇到的 -911 大概率是这类：包太大、或 zip 里含 APK 被拦截）。

v1.7 把两者拆开：

- **模块 zip 只有 40KB**，随便装；
- 补丁包 `nightpearl_patched_8.0.4.2.apk` 单独放到手机任意位置，模块会按顺序找：
  1. `/sdcard/Download/nightpearl_patched.apk`
  2. `/data/local/tmp/nightpearl_patched.apk`
  3. 模块目录下的 `nightpearl_patched.apk`

找不到就跳过补丁（不影响其他功能），Action 报告里会写「补丁包来源」。