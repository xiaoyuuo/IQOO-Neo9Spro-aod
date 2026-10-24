# 发行说明（可直接贴到 GitHub Release）

三个发行建议分开发布：

| Tag | 标题 | 附件 |
|---|---|---|
| `v2.9-ksu` | Neo9SP_aod · KernelSU 模块 v2.9 | `Neo9SP_aod_ksu_v2.9.zip` |
| `v3.0-ksu` | Neo9SP_aod · KernelSU 模块 v3.0 | `Neo9SP_aod_ksu_v3.0.zip` |
| `v2.4-lsp` | Neo9SP_aod · LSPosed 模块 v2.4 | `Neo9SP_aod_lsp_v2.4.apk` |

只有一个勾「Set as the latest release」（建议 `v3.0-ksu`）。

---

## v2.9-ksu

### Neo9SP_aod · KernelSU 模块 v2.9

**更新内容**

- 修复：`vivo_keyguard_aod_type` 改为**开机自动写入**（此前只在点「执行 / Action」时写，重启后可能掉回 1，表现就是"不实时刷新了"）
- 新增配置项：`AOD_TYPE`（1 局部 / 2 融合 / 3 全屏）、`MOUNT_SYSFS`、`SMART_AOD`、`OVERRIDES`
- 配置文件自动补键：升级模块后旧配置会自动补齐新增项，不用手动改
- 面板能力串改写增加自检，改不动时自动写兜底串

**附件**

- `Neo9SP_aod_ksu_v2.9.zip`（12KB）

**安装**

1. KernelSU 管理器 → 模块 → 从本地安装 → 选 zip；
2. 完整重启；
3. `config.ini` 里保持 `AOD_TYPE=2`。

**注意**：本模块需配合 LSPosed 模块使用；已知问题见 [docs/BUGS.md](../docs/BUGS.md)。

---

## v3.0-ksu

### Neo9SP_aod · KernelSU 模块 v3.0

**更新内容**

- 新增 `KILL_APP` 开关：应用配置后是否重启「熄屏显示」进程
  - `1`（默认，与 v2.9 行为一致）：改动立即生效
  - `0`：保持热进程，用于测试"进程冷启动是否让进 AOD 的黑屏变长"
- 其余功能与 v2.9 相同

**附件**

- `Neo9SP_aod_ksu_v3.0.zip`（13KB）

**安装**

同 v2.9；升级可直接覆盖，配置不会丢。

**注意**：本模块需配合 LSPosed 模块使用；已知问题见 [docs/BUGS.md](../docs/BUGS.md)。

---

## v2.4-lsp

### Neo9SP_aod · LSPosed 模块 v2.4

**更新内容**

- 新增实验性 hook：丢弃 `MSG_START_KEYGUARD_TO_AOD_ANIMATION`（`k5.a$c` / `AodKeyguardViewContainer$g` 的 `handleMessage`，`what == 0`）
  - 实测对"进 AOD 先黑一下"**无效**，黑帧来自显示层；想保守可删掉 `Main.java` 里 `hookAodAnimation(...)` 一行，即为 v2.3 行为
- 其余功能：只钩「熄屏显示」的 `r4.h.Q()/e0()/f0()`（机型白名单）、`SystemProperties` 里的全屏 AOD 属性
- 内置 `xposedscope` 推荐作用域：`com.vivo.nightpearl`、`com.android.systemui`

**附件**

- `Neo9SP_aod_lsp_v2.4.apk`（12KB）

**安装**

1. 安装 APK；
2. LSPosed 里启用，作用域点「推荐」；
3. 重启。

**注意**：需要配合 KernelSU 模块（v2.9 及以上）使用；已知问题见 [docs/BUGS.md](../docs/BUGS.md)。
