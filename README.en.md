# Maos Record — User Guide

[Русская версия](README.ru.md) · [Project overview](README.md) · [Download latest release](../../releases/latest)

Maos Record is a native screen recorder for Intel Macs running macOS Catalina 10.15 or later. It records the selected display to an MP4 file and can add an audio input and camera overlay.

## Installation

1. Open **[GitHub Releases](../../releases/latest)**.
2. Download `MaosRec-macOS-10.15-Intel.dmg`.
3. Open the DMG and drag **Maos Record.app** onto **Applications**.
4. Open Applications, right-click **Maos Record**, choose **Open**, and confirm.

The extra confirmation is required because public builds are ad-hoc signed. If macOS does not show the Open button, run this once in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/Maos Record.app"
```

Only use this command for a package downloaded from this project's official Releases page. You can compare the package checksum with `SHA256SUMS.txt`.

## First launch permissions

Open **System Preferences → Security & Privacy → Privacy** and allow:

- **Screen Recording** — always required;
- **Camera** — required only for a camera overlay;
- **Microphone** — required only when audio is enabled.

Restart Maos Record after granting Screen Recording permission.

## Recording

1. Select a display in the Screen section.
2. Enable or disable the camera overlay.
3. Choose the camera position and size.
4. Enable or disable audio and select an input device.
5. Open Settings to choose the quality and recordings folder.
6. Click **Start recording**.
7. Click **Stop recording** when finished.

The default Balanced profile records at up to 720p and 15 fps. Use Economy 540p/12 fps on a Mac with 2 GB of RAM or a very slow CPU. Smooth 720p/30 fps requires more resources.

## Audio

Maos Record records the selected audio input, normally the built-in microphone. Catalina does not expose direct system-audio capture to ordinary applications. To record application audio, install a trusted virtual audio device and select it in Maos Record.

## Automatic updates

Maos Record checks [GitHub Releases](../../releases/latest) after launch and every six hours when automatic checks are enabled. If a newer version exists, the app can:

1. download the release ZIP;
2. verify it against `SHA256SUMS.txt`;
3. verify the application identity, version, and code signature;
4. replace the installed copy and relaunch.

Stop an active recording before installing an update. Maos Record must be running from Applications or another writable local folder, not directly from the DMG.

## Uninstalling

Quit Maos Record and move it from Applications to Trash. To remove saved preferences:

```bash
defaults delete com.maosrec.app
```

Recorded MP4 files are not removed automatically.
