# Build + install Piposh 2 APK to a connected Android device.
# Prerequisites:
#   1. USB cable + Developer options → USB debugging ON
#   2. Phone set to File Transfer (MTP), accept the RSA prompt
#   3. Godot 4.7.1 export templates installed

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $root 'build\Piposh2.apk'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;" + $env:Path

if (-not (Test-Path $adb)) { throw "adb not found at $adb" }

Write-Host 'Devices:'
& $adb devices -l
$devices = & $adb devices | Select-String "`tdevice$"
if (-not $devices) {
  Write-Host @"

No authorized device. On the phone:
  Settings → About phone → tap Build number 7×
  Settings → Developer options → enable USB debugging
  Replug USB → set USB mode to File Transfer
  Accept 'Allow USB debugging?' prompt

Then re-run this script.
"@
  exit 2
}

if (-not (Test-Path $apk)) {
  Write-Host "APK missing — exporting..."
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null
  & godot_console --path $root --headless --export-debug Android $apk
}

Write-Host "Installing $apk ..."
& $adb install -r $apk
Write-Host 'Launching...'
& $adb shell am start -n com.piposh.piposh2/com.godot.game.GodotApp
Write-Host 'Done.'
