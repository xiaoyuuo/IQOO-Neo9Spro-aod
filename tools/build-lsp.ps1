<#
  build-lsp.ps1 —— 无 Gradle 构建 LSPosed 模块（javac → d8 → aapt2 → zipalign → apksigner）

  依赖：
    - JDK 11+（JAVA_HOME 或 -JavaHome）
    - Android SDK build-tools 35.0.0、platforms/android-36
    - Xposed API 82 jar（编译期 classpath，不打进 dex）
      可从 Maven Central 取：de.robv.android.xposed:api:82

  示例：
    pwsh tools/build-lsp.ps1 -XposedApiJar lib/xposed-api-82.jar
    pwsh tools/build-lsp.ps1 -Sdk "C:\Android\Sdk" -Out dist/Neo9SP_aod_lsp.apk
#>
param(
    [string]$Src = (Join-Path $PSScriptRoot "..\lsp"),
    [string]$Out = (Join-Path $PSScriptRoot "..\dist\Neo9SP_aod_lsp.apk"),
    [string]$Sdk = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$XposedApiJar = (Join-Path $PSScriptRoot "..\lib\xposed-api-82.jar"),
    [string]$BuildTools = "35.0.0",
    [string]$PlatformJar = "android-36\android.jar"
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $Sdk) { throw "need -Sdk or ANDROID_SDK_ROOT" }
$BT  = Join-Path $Sdk "build-tools\$BuildTools"
$ANDROID_JAR = Join-Path $Sdk "platforms\$PlatformJar"
$JAVA    = if ($JavaHome) { Join-Path $JavaHome "bin\java.exe" } else { "java" }
$JAVAC   = if ($JavaHome) { Join-Path $JavaHome "bin\javac.exe" } else { "javac" }
$KEYTOOL = if ($JavaHome) { Join-Path $JavaHome "bin\keytool.exe" } else { "keytool" }
$JAR     = if ($JavaHome) { Join-Path $JavaHome "bin\jar.exe" } else { "jar" }
$D8_JAR    = Join-Path $BT "lib\d8.jar"
$APKSIGNER = Join-Path $BT "lib\apksigner.jar"
$ZIPALIGN  = Join-Path $BT "zipalign.exe"
$AAPT2     = Join-Path $BT "aapt2.exe"

$OBJ = Join-Path $PSScriptRoot "..\build\obj"
$KS  = Join-Path $PSScriptRoot "..\build\debug.keystore"
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $KS)  | Out-Null

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Check($n) { if ($LASTEXITCODE -ne 0) { throw "FAILED: $n (exit $LASTEXITCODE)" } }

if (-not (Test-Path $KS)) {
    Step "gen debug keystore"
    & $KEYTOOL -genkeypair -keystore $KS -alias androiddebugkey -storepass android `
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US" 2>&1 | Out-Null
}

if (Test-Path $OBJ) { Remove-Item $OBJ -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$OBJ\classes" | Out-Null

Step "javac"
$javaFiles = Get-ChildItem $Src -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if (-not $javaFiles) { throw "no java sources under $Src" }
$javacArgs = @("--release", "11", "-encoding", "UTF-8", "-nowarn",
    "-cp", "$ANDROID_JAR;$XposedApiJar", "-d", "$OBJ\classes") + $javaFiles
& $JAVAC @javacArgs
Check "javac"

Step "d8"
& $JAR cf "$OBJ\classes.jar" -C "$OBJ\classes" . | Out-Null
Check "jar"
& $JAVA -cp $D8_JAR com.android.tools.r8.D8 --release --min-api 29 `
    --lib $ANDROID_JAR --classpath $XposedApiJar --output $OBJ "$OBJ\classes.jar" 2>&1 | Write-Host
if (-not (Test-Path "$OBJ\classes.dex")) { throw "d8 produced no classes.dex" }

Step "aapt2 compile"
if (Test-Path "$Src\res") {
    & $AAPT2 compile --dir "$Src\res" -o "$OBJ\res.zip"
    Check "aapt2 compile"
}

Step "aapt2 link"
$linkArgs = @("link", "-o", "$OBJ\base.apk", "-I", $ANDROID_JAR,
    "--manifest", "$Src\AndroidManifest.xml",
    "--min-sdk-version", "29", "--target-sdk-version", "36")
if (Test-Path "$OBJ\res.zip") { $linkArgs += @("$OBJ\res.zip") }
& $AAPT2 @linkArgs
Check "aapt2"

Step "pack"
Copy-Item "$OBJ\base.apk" "$OBJ\unsigned.apk" -Force
$zip = [System.IO.Compression.ZipFile]::Open((Resolve-Path "$OBJ\unsigned.apk"), 'Update')
try {
    $e = $zip.CreateEntry("classes.dex", [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $e.Open(); $b = [IO.File]::ReadAllBytes("$OBJ\classes.dex"); $s.Write($b, 0, $b.Length); $s.Close()
    Get-ChildItem "$Src\assets" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $e2 = $zip.CreateEntry("assets/$($_.Name)", [System.IO.Compression.CompressionLevel]::Optimal)
        $s2 = $e2.Open(); $b2 = [IO.File]::ReadAllBytes($_.FullName); $s2.Write($b2, 0, $b2.Length); $s2.Close()
    }
} finally { $zip.Dispose() }

Step "zipalign"
& $ZIPALIGN -f 4 "$OBJ\unsigned.apk" "$OBJ\aligned.apk"
Check "zipalign"

Step "apksigner"
if (Test-Path $Out) { Remove-Item $Out -Force }
& $JAVA -jar $APKSIGNER sign --ks $KS --ks-pass pass:android --key-pass pass:android `
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false `
    --out $Out "$OBJ\aligned.apk"
Check "apksigner"

Write-Host "`nOUT -> $Out" -ForegroundColor Green
