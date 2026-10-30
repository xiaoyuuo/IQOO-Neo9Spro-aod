$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $root 'build'
$sdk = 'C:\Users\XY\AppData\Local\Android\Sdk'
$aapt2 = Join-Path $sdk 'build-tools\35.0.0\aapt2.exe'
$zipalign = Join-Path $sdk 'build-tools\35.0.0\zipalign.exe'
$apksigner = Join-Path $sdk 'build-tools\35.0.0\apksigner.bat'
$d8 = Join-Path $sdk 'build-tools\35.0.0\d8.bat'
$androidJar = Join-Path $sdk 'platforms\android-36\android.jar'
$apiJar = 'D:\dsh\work\vivo_eq\api-82.jar'
$javac = 'E:\java21\bin\javac.exe'
$jar = 'E:\java21\bin\jar.exe'
$keytool = 'E:\java21\bin\keytool.exe'

Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $build, "$build\gen", "$build\classes", "$build\dex" | Out-Null

Push-Location $root
& $aapt2 compile --dir res -o "$build\res.zip"
& $aapt2 link -o "$build\unsigned.apk" -I $androidJar --manifest AndroidManifest.xml -A assets -R "$build\res.zip" --auto-add-overlay --java "$build\gen"
Pop-Location

$sources = Get-ChildItem "$root\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& $javac -encoding UTF-8 -source 11 -target 11 -Xlint:-options -classpath "$androidJar;$apiJar" -d "$build\classes" $sources

Push-Location "$build\classes"
& $jar cf "$build\classes.jar" .
Pop-Location

& $d8 --min-api 26 --release --lib $androidJar --lib $apiJar --output "$build\dex" "$build\classes.jar"

Push-Location $build
& $jar uf unsigned.apk -C dex classes.dex
Pop-Location

& $zipalign -f 4 "$build\unsigned.apk" "$build\aligned.apk"

$ks = "$build\eq.keystore"
if (-not (Test-Path $ks)) {
    & $keytool -genkeypair -v -keystore $ks -storepass android -alias eq -keypass android `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Vivo Eq Enabler, OU=DSH, O=Local, L=Local, ST=Local, C=CN"
}

& $apksigner sign --ks $ks --ks-pass pass:android --key-pass pass:android `
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
    --out "$build\VivoEqEnabler-1.14.apk" "$build\aligned.apk"

& $apksigner verify --verbose "$build\VivoEqEnabler-1.14.apk"

Get-Item "$build\VivoEqEnabler-1.14.apk" | Select-Object FullName, Length
