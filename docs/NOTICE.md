# 第三方与归属说明

## 本项目自身

- 源码、KernelSU 模块脚本、LSPosed 模块代码、构建与分析工具：MIT，见 [LICENSE](../LICENSE)。
- 作者：酷安 @小雨爱分享。

## 编译期依赖（不随本仓库分发）

| 依赖 | 用途 | 许可 |
|---|---|---|
| `de.robv.android.xposed:api:82` | LSPosed 模块编译（只做 classpath，不打进 APK） | Apache License 2.0 |

需要自行下载：`lib/README.md` 里有地址。

## 思路来源

- 全屏 AOD 的可行性来自酷安 @Dchigve 的 iQOO Neo10 模块（`ro.vivo.keyguard_full_aod.enable=1`），
  本项目未使用其代码，仅沿用同一属性思路并在 Neo9S Pro 上重新适配。

## 修改过的系统组件

- 仓库**不包含**任何 vivo 应用或其修改版 APK。
- `tools/patch_apk.py` 只是工具，需用户用自己设备导出的 APK 自行生成补丁，产物请勿公开分发。