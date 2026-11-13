# Neo9SP_AOD（KSU 模块 v4.0）

开启系统隐藏息屏AOD。熄屏不是落幕，是留给往事的留白。长夜漫过屏幕，微光替我念想。

## v4.0：换思路，上传感器桥（app_process）

前几版一直是纯 shell 在猜状态：事件源选错、通知洪流重置计时器、亮度被钉住后不跟环境光……
这一版按“换思路”改成 **shell 管策略 + Java 进程管传感器**：

```
sensor.dex  (app_process, root)
  ├─ 读 TYPE_LIGHT      → 有光就把 aod_bl_level 恢复成 956
  ├─ 读加速度计         → moving / still 秒数
  ├─ 每秒写 sensor.state（lux / bright / moving / still / ts）
  └─ 读 sensor.cmd：sleep → PowerManager.goToSleep()（真熄屏）
        ↑
aodkeep.sh  ── 阶梯变暗 / 来消息恢复 / 亮屏撤销
        每一步先看 sensor.state：lux ≥ AOD_LIGHT_SKIP 就跳过（有光不压暗）
        300 秒那一步：让传感器桥 goToSleep，桥不在才退回写 aod_bl_level=1
```

新增配置：

```ini
SENSOR_BRIDGE=1     # 1=启用传感器桥
AOD_LIGHT_SKIP=80   # lux 超过就认为“有光”，不压暗、不熄屏
```

Action 报告里新增：

```
传感器桥 : 运行中  pid=xxxx
  状态   : ts=… lux=12 bright=0 moving=0 still=37
  日志   : /data/adb/iqoo_pd2339_fullaod/sensor.log
```

### 注意
`sensor.dex` 是通过 `app_process` 直接跑在 root 下的，如果这台机器上
`ActivityThread.systemMain()` 取不到 Context，`sensor.log` 里会有一行
`FATAL ...`，这时 AOD 阶梯仍然工作，只是“有光恢复/真熄屏”两项失效——
把 `sensor.log` 发我即可，我改另一种取 Context 的方式。

## v3.7：状态机只认 displayState

## v3.5：解析错字段，阶梯只走了一步就停

v3.4 的日志长这样：

```
11:04:20 timer start: base=956 steps=15:60,60:35,300:1
11:04:20 ev: I/power_screen_state(6726): [0,2,0,0,1809]
11:04:20 ev: I/power_screen_state(6726): [0,4,0,0]
11:04:20 ev: I/power_screen_state(6726): [1,0,0,0]
11:04:20 wake/unlock, timer cancelled
```

`power_screen_state` 的字段是 **`[wakefulness, displayState, ...]`**，
v3.4 把第一个字段当成了 displayState，于是 `[1,0,0,0]`（熄屏瞬间）被当成“进 AOD”，
紧接着 `screen_toggled: 1` 又撤销一次——计时器就这么反复起停，
所以只暗了一档（60%）就停住，后面 35% 和全黑都走不到。

v3.5：

- 改成取第二个字段（2=亮屏，3/4=DOZE），`screen_toggled` 仍然作为备用触发；
- **来真消息 → 先把亮度恢复成原厂 956，再重新计时**（之前只重计时，所以你觉得“来消息不亮”）；
- `AUTO_BRIGHT` 默认改成 **1**：你反馈“手电筒照也不变亮、室外看不见”，
  手动亮度模式下本来就不会跟环境光，交给系统光线传感器才能室内外都看清（不想要改回 0）。

## v3.4：v3.3 为什么还是“没效果”

v3.3 的 Action 日志暴露了两个问题：

**1）计时器被“假消息”无限重置**

`notification_enqueue` 事件里全是这类东西，几秒一次：

```
com.vivo.musicwidgetmix ... channel=VivoMusicWidgetMix
com.luna.music ... groupKey=player_service
```

音乐小部件/播放器在持续重发通知事件。v3.3 把每一条都当成“来消息”，
于是计时器不停从头开始，**永远等不到 15 秒**，自然一步都不暗。

v3.4 过滤掉 `musicwidget` / `VivoMusicWidgetMix` / `PLAY_SERVICE` / `player_service`
这类噪声，只认真消息。

**2）进 AOD 的信号源选错了**

v3.3 只认 `power_screen_state=[3/4`。日志里能稳定看到的是
`I/screen_toggled(27544): 1`（亮屏），说明这台机器上 `screen_toggled` 才是必到的信号。
v3.4 两种都认：

- `screen_toggled: 0` 或 `power_screen_state` 为 1/3/4 → 开始计时
- `screen_toggled: 1` 或 `power_screen_state` 为 2 → 撤销

（日志里 `guard` 的 `WAKE (screen_toggled=1)` 已经证明这条链路是通的。）

## v3.3：阶梯变暗 + 修「守护进程不再重启」

### v3.2 为什么一点效果都没有

`aod.log` 只有三行：

```
10-25 10:32:21 ==== aodkeep v3.2 start (pid 3172) ====
10-25 10:32:21 watching events (round 1)
10-25 10:32:39 aodkeep stopped
```

Action 里 `fa_aod_stop` 杀掉了守护进程，然后 `fa_aod_start` 里
`fa_aod_running` 用 `ps | grep aodkeep.sh` 兜底判断——**刚被杀掉的进程还没被回收，
grep 仍然命中**，于是日志写“already running”，再也不重启。
所以你看的一分钟里根本没有守护进程在跑。

v3.3 把 `running` 判定改成**只看 pid 文件 + `kill -0`**；启动前先把残留实例清干净，
启动后再校验一次 pid 文件。guard.sh 也一起改了（之前同样“运行中 pid=”）。

### 新的阶梯（按你的要求）

```
进入 AOD ──15秒──> 60%        AOD_STEPS 第一档
        ──60秒──> 35%        第二档
        ──300秒─> 全黑（user=1）  第三档 ≈ 熄屏
来消息   ──> 从 15 秒重新开始
亮屏/解锁 ─> 立即撤销
```

配置：

```ini
AOD_STEPS=15:60,60:35,300:1     # 秒:亮度百分比，<=1 表示黑掉
AOD_OFF_LEVEL=1
AOD_DEBUG=1                     # 记录每个事件，排查用
```

### 另一个坑：`aod_bl_level` 不是裸数字

实测节点内容是：

```
user=956,current=0
```

所以 v3.2 直接 `echo 300 > aod_bl_level` 是错的。v3.3 改成按
`user=N` → `user=N,current=N` → 裸数字 的顺序试写，读到 `user=N` 就记住格式，
后续都用这个格式。每次写入都会记日志：

```
try 'user=300' -> user=300
format ok: user=%s
```

## v3.2：熄屏显示超时（变暗 → 黑掉），防烧屏

### 探针查到的落点

| 项 | 结果 |
|---|---|
| `/sys/class/backlight/*` | **不存在**（所以只能用 `/sys/lcm/` 的节点） |
| `/sys/lcm/aod_bl_level` | **存在，`-rw-rw-r-- system system`** → root 可写，这是 AOD 背光档位 |
| `/sys/lcm/bl_level` | 存在，正常亮屏背光 |
| `settings put` | 探针里 **rc=0，写得进去**；v3.1 日志里的失败只发生在刚开机那几秒 |
| LSPosed | 已安装（`/data/adb/lspd`、`zygisk_lsposed`） |
| AOD 类型 | `screen_off_remind_aod_type=1`（全屏），`vivo_keyguard_aod_type=2` |

### 新增守护 `aodkeep.sh`

进熄屏显示后按时间轴动手脚，全部通过 `/sys/lcm/aod_bl_level`：

```
进入 AOD ──60s──> 变暗到 25%（AOD_DIM_SEC / AOD_DIM_PCT）
        ──8min──> 写 AOD_OFF_LEVEL（默认 1≈全黑），等于不显示（AOD_OFF_SEC）
来通知    ──> 重新计时（先让通知正常显示一轮）
亮屏/解锁 ──> 立刻撤销定时器，交回系统
```

配置（`config.ini`，改完点一次 Action）：

```
AOD_TIMEOUT=1        # 1=开 0=关
AOD_DIM_SEC=60       # 多久后变暗
AOD_DIM_PCT=25       # 暗到原来的百分之几
AOD_OFF_SEC=480      # 多久后黑掉（8 分钟）
AOD_OFF_LEVEL=1      # 黑掉时写的档位，不要填 0
```

> 事件源仍是 event log（`power_screen_state` / `notification_enqueue`），
> 事件驱动不轮询；两个 `sleep` 定时器只在 AOD 期间存在，亮屏即杀。

### v3.2 还修了「原厂串采集」

v3.1 的日志里是 `umount ok` 紧接着 `refresh_orig: still mounted, skip` —— 说明
bind mount 叠了不止一层，一次 umount 只剥掉一层。v3.2 改成 `fa_umount_all`
（循环剥到干净），并且**每次开机在 post-fs-data 里、挂载之前**另存一份
`orig_boot.txt` / `orig_boot_label.txt`。Action 里新增：

```
开机第一现场原厂串（orig_boot）: ...
              原厂标签        : ...
```

如果这里显示 `support_full_screen=0`，说明模块确实在起作用；
如果显示 `1`，说明这台 ROM 原生就支持全屏 AOD，模块本身可以不装（`DISABLE=1` 试试）。

## v3.1：先止血 + 装探针（这一版不吹“已修好”）

从 v3.0 的 Action 报告里读到的三件事：

1. **亮度守卫其实没工作**：`guard.log` 里全是
   `Failure calling service settings: Failed transaction (2147483646)`。
   KSU 的 su 环境里 `settings put` 被拦了（[同类问题](https://kernelsu.jizhiku.net/archives/299/)），
   所以 v3.0 那套“重下发亮度”等于没执行。
2. **真正错位的是两个亮度值**：报告里同一时刻
   `screen_brightness=0` 而 `screen_brightness_float=0.176`（=45/255）。
   控制中心看的是 int（显示最低），屏幕吃的是 float（17.6%）——
   正好就是“滑块最低、屏还亮一档，再拖一下才真暗”。
3. **原始面板串/标签是脏数据**：日志里 `chcon ok: u:object_r:adb_data_file:s0`、
   「原始内容」和「当前可见」一样（都是 `support_full_screen=1`），
   说明当初是在“已经挂载”的状态下抓的原厂值，chcon 等于空操作。

v3.1 做了：

- 每次 Action 重挂前先 umount，再重新采集原厂串与标签（`fa_refresh_orig`）；
- Action 末尾新增**探针**，会打印：
  - `/sys/lcm/` 下所有节点和值（含 `vlcm_bl_level` / `vlcm_aod_bl_level`，这是后面做“超级暗”的落点）；
  - 4 种 settings 写入通道的可用性（root / cmd / setpriv 2000 / su 2000）；
  - LSPosed 是否安装、nightpearl 补丁包是否存在；
  - 当前电源/显示状态。

> 先把 Action 报告里的「探针」整段发回来，下一版才能确定
> “8 分钟自动熄屏 + 长时间无操作变暗”到底该从哪个口子下手（纯 shell 无法调用 PowerManager 熄屏）。

### 立刻降低烧屏风险（不用等下一版）

`config.ini` 里把熄屏亮度调低，点一次 Action 生效：

```
AOD_BRIGHTNESS=300    # 原值 956；越小越暗，200~400 之间可试
```

## v3.0：修「熄屏来消息后，解锁亮度卡住不回落」

### 症状
亮度手动拉到最低 → 熄屏 → 来消息（熄屏显示会亮一点）→ 解锁后屏幕仍比最低亮一档，
控制中心滑块却显示最低；把滑块往上拉一下再拉回来，屏幕才真正变暗。

### 两个原因（v3.0 各修一个）

1. **「熄屏显示」进程读不到伪造的面板串**
   `com.vivo.nightpearl` 的 `AndroidManifest` 带 `sharedUserId="android.uid.system"`，
   进程跑在 **system_app** 域。v2.9 的 `sepolicy.rule` 只放行了 `platform_app` /
   `untrusted_app` 读 `adb_data_file`，**没有 system_app**。结果：SystemUI 插件读到
   「支持全屏」，而熄屏显示本体读到的还是「不支持」→ 两边亮度判断不一致，
   表现正是「先最暗、再抬一档」，并且熄屏显示退出时不会把亮度还回去。
   → v3.0 补上 `allow system_app adb_data_file ...`；`chcon` 也改成
   「原标签 → system_file → vendor_file」回退，chcon 失败不再放弃挂载。

2. **熄屏显示退出时少了一次亮度下发**
   这是系统侧的行为，我们改不动它的 Java，于是加一个「亮度守卫」：
   监听 `power_screen_state` / `screen_toggled` 事件，亮屏/解锁后
   在 0.8s / 2.5s / 5s 各把**你当前的亮度**重新下发一次（先 ±3 级再回原值，
   肉眼看不出来），等于替你做了「拖一下滑块」这个动作。

### 怎么验证
1. 装完重启，点一次模块的「执行 / Action」。
2. 报告里确认：`亮度守卫 : 运行中`，并且 `假文件标签` 这行有值。
3. 复现：亮度拉到最低 → 熄屏 → 发一条消息 → 解锁 → 看亮度是否回到最低。
4. 不管成功失败，把 Action 报告（尤其「守卫日志」那 20 行）发回来。
   日志里应该能看到 `WAKE (...)` 和三次 `refresh[...]  int=... float=...`。

### 新增配置（`/data/adb/iqoo_pd2339_fullaod/config.ini`）
| 键 | 默认 | 说明 |
|---|---|---|
| `BRIGHT_GUARD` | 1 | 亮度守卫总开关 |
| `GUARD_DEBUG` | 1 | 记录每次亮屏前后亮度（排查完可改 0） |
| `SMART_AOD` | 1 | 原厂「智能熄屏」：交给系统自己的传感器逻辑 |
| `AUTO_BRIGHT` | 0 | 打开系统自动亮度（光线传感器），设 1 即生效 |

> `SMART_AOD=1` 用的是 vivo 自己的 `persist.vivo.phone.smart_aod`，
> 行为跟原厂一致；`AUTO_BRIGHT=1` 打开的是系统自带自动亮度。
> 这两个都是「用原厂实现」，不是我们另写的传感器算法——先用它试，
> 不行再上自定义守护进程。

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
---

# v6.2 更新内容 / 已知问题 / 开源

## 更新内容（相对 v4.5）
- **面板串标签修正**：/sys/lcm/aod_disp_info 的真实 SELinux 标签是
  u:object_r:sysfs_oled_hbm:s0（见 /vendor/etc/selinux/vendor_file_contexts），
  伪造副本不再用 db_data_file，并新增 llow ksu ... relabelfrom/relabelto。
- **面板串落地方式**：SYSFS_MODE=auto — 先尝试直接写真实节点（保留原标签），
  失败再 bind mount；挂载后回读 /proc/mounts 校验。
- **AOD 亮度**：面板串里的 od_brightness 对全屏 AOD 无效（实测 956 与 4000 一样暗），
  真正生效的是 /sys/lcm/aod_bl_level；AOD_FIX_LEVEL > 0 时进 AOD 写固定档位。
- **阶梯与真熄屏**：AOD_STEPS 恢复 15s/60s/300s；SENSOR_BRIDGE=1 时到点调
  PowerManager.goToSleep()，失败退化 input keyevent 223。
- **AOD 类型联动**：MODEWATCH 每 5 秒读 ivo_keyguard_aod_type，
  切到「局部」自动把面板串改回 support_full_screen=0 并重启熄屏显示进程。
- **补丁 APK 路线关闭**（PATCH_APK=0）：本机安装报 -911、bind mount 也挂不上。
- Action 报告新增：读面板串(system_app)、假文件标签、当前可见、面板/LCM 诊断段。

## 已知问题（都属于设备/固件边界，模块层无解）
1. **秒表 / 倒计时 / 音乐进度的数字**在 AOD 上不显示（显示  1:--）。
   面板是 Visionox RM692H5（pd2339_panel_visionox_rm692h5_cmd），
   /vendor/etc 里没有它的 dbi，初始化码编在内核 LCM 驱动里；
   support_video_aod=1 只会引入渲染 bug，不会显示数字。
2. **熄屏瞬间轻微闪烁**：固件 doze → doze_suspend 硬切，切的那一帧按寄存器值显示。
3. **设置页「局部/全屏」选择器**：需要 LSPosed 模块（本机 patch APK 装不上、挂不上）。
4. 切到「局部」后布局偶尔不重排：等 MODEWATCH 生效或手动点一次 Action。

## 开源
- 协议：MIT
- 作者：酷安 @小雨爱分享
- LSPosed 模块源码：Neo9SP_AOD_lsposed_src_v2.5.zip（Main.java / AndroidManifest.xml / arrays.xml / build.ps1 / LICENSE）
---

# v7.0 卸载清理（重点）

## 问题
「直接删除模块 + 软重启」后仍有残留：
- 设置里还显示「局部/全屏」选择器
- 功耗偏高、发热

原因：KSU 的 bind mount 是**内核层挂载**，卸载模块不会自动 umount，软重启也不会清；
而旧版 uninstall.sh 只 umount 一次（叠层时剥不干净），**也没有还原 settings**。

## 现在的清理逻辑（uninstall.sh）
1. 停掉所有守护进程（guard / aodkeep / modewatch / sensor bridge / logcat）
2. **还原 settings**：ivo_keyguard_aod_type、screen_off_remind_aod_type、
   ull_screen_aod_enabled/show —— 首次运行时已备份到 /data/adb/iqoo_pd2339_fullaod/orig_settings.txt
3. **循环 umount** 面板串 /sys/lcm/aod_disp_info（最多 8 层）与夜明珠 base.apk
4. killall com.vivo.nightpearl，让它按真实面板串重新初始化
5. 删除工作目录、补丁副本、日志

日志：/data/local/tmp/aod_uninstall.log

## 手动兜底
开机时会把同一份脚本复制到：
`
/data/local/tmp/aod_clean.sh
`
如果模块是「直接删除」而没走卸载流程，执行一次即可立刻清干净（不用重启）：
`
sh /data/local/tmp/aod_clean.sh
`

## 验证
卸载（或手动执行清理）后：
`
mount | grep aod_disp_info          # 应该没有输出
settings get secure vivo_keyguard_aod_type   # 应回到你原来的值
`
再进设置看「熄屏显示」，选择器应该消失；功耗在几分钟内回落。
---

# v7.2

## 1. 卸载残留的另一半：settings 备份被污染
v7.0 的清理会“写回备份”，但第一份备份是在模块已经写过 settings 之后采的
（日志里能看到 estore settings: vivo_keyguard_aod_type -> 3），
等于把“全屏 AOD”又还原回去，于是清理完选择器还在。

v7.2 改为**删除**这些键，交回系统默认：
`
vivo_keyguard_aod_type
screen_off_remind_aod_type
full_screen_aod_enabled
full_screen_aod_show
`

## 2. 局部熄屏时时钟偏左、不居中
根因：ivo_keyguard_aod_type 只影响 AOD 窗口 title，
真正决定局部/全屏的是 screen_off_remind_aod_type（0=局部 1=全屏）。
旧版 a_current_aod_type 优先读前者，所以在设置里选「局部」时，
面板串仍按全屏处理 → 夜明珠用全屏布局（靠左、上下随机漂移）。

v7.2 改为优先读 screen_off_remind_aod_type：
- 局部（0）→ 面板串 support_full_screen=0 → 原厂居中布局
- 全屏（1）→ 面板串 support_full_screen=1

切完类型等 30 秒（MODEWATCH_SEC）或点一次「执行」即可生效。