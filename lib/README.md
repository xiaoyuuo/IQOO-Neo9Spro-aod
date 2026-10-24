# lib/

构建 LSPosed 模块需要一个编译期依赖的 Xposed API jar（不会打进 dex）：

```
lib/xposed-api-82.jar
```

从 Maven Central 获取：

```
https://repo1.maven.org/maven2/de/robv/android/xposed/api/82/api-82.jar
```

或直接用本仓库的构建脚本参数指定：

```
pwsh tools/build-lsp.ps1 -XposedApiJar "D:\path\to\xposed-api-82.jar"
```