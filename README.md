<h1>
  <img src="assets/plezy.png" alt="Popkino logo" height="24" style="vertical-align: middle;" />
  Popkino
</h1>

A client for Plex, Jellyfin, and Emby with a TV-friendly interface, for Android TV, desktop, and mobile.

Popkino is based on [Plezy](https://github.com/edde746/plezy). It is an independent project, neither developed nor
endorsed by the Plezy project. See [TRADEMARKS.md](TRADEMARKS.md) and [NOTICE.md](NOTICE.md).

## Download

Releases are published on GitHub only (no app store). The links point to the latest release, except for Android
(see below).

| Platform | Download |
| --- | --- |
| Android (arm64-v8a: most recent TVs and phones) | [Releases page](https://github.com/adrien24/popkino/releases), file `popkino-android-arm64-v8a-<version>.apk` |
| Android (armeabi-v7a: Fire TV Stick and entry-level TVs) | [Releases page](https://github.com/adrien24/popkino/releases), file `popkino-android-armeabi-v7a-<version>.apk` |
| Android (x86_64) | [Releases page](https://github.com/adrien24/popkino/releases), file `popkino-android-x86_64-<version>.apk` |
| iPhone / iPad | [IPA (unsigned)](https://github.com/adrien24/popkino/releases/latest/download/popkino-ios.ipa) |
| macOS | [DMG](https://github.com/adrien24/popkino/releases/latest/download/popkino-macos.dmg) |
| Windows | [Installer](https://github.com/adrien24/popkino/releases/latest/download/popkino-windows-installer.exe) · [portable x64](https://github.com/adrien24/popkino/releases/latest/download/popkino-windows-x64-portable.7z) · [portable arm64](https://github.com/adrien24/popkino/releases/latest/download/popkino-windows-arm64-portable.7z) |
| Linux x64 | [.deb](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.deb) · [.rpm](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.rpm) · [.pkg.tar.zst](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.pkg.tar.zst) · [.flatpak](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.flatpak) · [.AppImage](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.AppImage) · [portable tar.gz](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-x64.tar.gz) |
| Linux arm64 | [.deb](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.deb) · [.rpm](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.rpm) · [.pkg.tar.zst](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.pkg.tar.zst) · [.flatpak](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.flatpak) · [.AppImage](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.AppImage) · [portable tar.gz](https://github.com/adrien24/popkino/releases/latest/download/popkino-linux-arm64.tar.gz) |

Android releases may be published as pre-releases, which GitHub's "latest release" links ignore: download the APK
from the [Releases page](https://github.com/adrien24/popkino/releases) instead.

## Installing without a store signature

Popkino is not distributed through app stores and the Windows and Apple builds are not signed with a paid
developer certificate, so each system shows a warning the first time.

- **Android**: download the `.apk` that matches your device, then allow installing apps from unknown sources for the
  app you use to open it (browser, file manager, or `adb install -r popkino-android-<abi>-<version>.apk` on a TV).
  Once installed, Popkino can update itself from the "update available" button on the home screen.
- **Windows**: SmartScreen may show "Windows protected your PC". Click "More info", then "Run anyway".
- **macOS**: if the system refuses to open the app, right-click it and choose "Open", then confirm ("Open Anyway" in
  System Settings > Privacy & Security). Alternatively, remove the quarantine flag:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Popkino.app
  ```

- **iPhone / iPad**: the IPA is unsigned. Install it with [AltStore](https://altstore.io) or
  [Sideloadly](https://sideloadly.io). With a free Apple account, the app expires after 7 days and must be
  re-signed.

## Verifying the APK

Every Android release is signed with the same key. Before installing, you can check the certificate of the APK:

```bash
apksigner verify --print-certs popkino-android-<abi>-<version>.apk
```

The SHA-256 digest of the signing certificate must be:

```
9F:6F:21:45:72:D5:5E:87:F4:AE:6D:C1:34:C7:F4:AA:DF:47:9A:15:99:8E:A2:79:55:D4:0E:B5:BA:C3:46:24
```

## Troubleshooting: updating on Fire TV

When Popkino downloads an update, Android asks you to allow it to install apps. On some Fire OS versions, Popkino does
not appear in the "Install unknown apps" list. From a computer on the same network, grant the permission with adb:

```bash
adb shell appops set io.github.adrien24.popkino REQUEST_INSTALL_PACKAGES allow
```

## License

Popkino is licensed under the [GNU General Public License v3.0](LICENSE), like Plezy. See [NOTICE.md](NOTICE.md) for
the modifications made to the original work.
