# Android install

## Status

- Debug APK: `build/Piposh2.apk` (~84 MB, day-1 movie subset)
- Package: `com.piposh.piposh2`
- Full render_model (~1 GB / 85 movies) lives in the project for desktop; the APK ships a playable subset so export finishes in reasonable time.

## One-shot install

```powershell
.\scripts\install_android.ps1
```

## Phone setup (required)

ADB currently needs the device **authorized**:

1. Enable **Developer options** (tap Build number 7 times)
2. Enable **USB debugging**
3. USB mode: **File Transfer / MTP** (not Charge only)
4. Accept the **Allow USB debugging?** RSA dialog on the phone

Check:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
```

You want `device` (not `unauthorized` / empty).

## Rebuild APK

```powershell
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
godot_console --path E:\development\piposh_2_godot --headless --export-debug Android E:\development\piposh_2_godot\build\Piposh2.apk
```

## Notes

- Editor Settings → Export → Android: Java SDK + Android SDK paths are configured
- Export templates: `4.7.1.stable`
- Debug keystore: Godot default or `android/debug.keystore`
