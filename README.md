<p align="center">
  <img src="docs/assets/logo.svg" width="128" height="128" alt="MaosRec logo">
</p>

<h1 align="center">MaosRec</h1>

<p align="center">A lightweight, open-source screen recorder for older Intel Macs.</p>

<p align="center">
  <a href="README.en.md">English</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <a href="../../actions/workflows/build.yml"><img alt="Build" src="../../actions/workflows/build.yml/badge.svg"></a>
  <img alt="macOS 10.15+" src="https://img.shields.io/badge/macOS-10.15%2B-111827?logo=apple">
  <img alt="Intel x86_64" src="https://img.shields.io/badge/Intel-x86__64-0071C5?logo=intel">
  <img alt="Swift AppKit" src="https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&amp;logoColor=white">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-22C55E">
</p>

MaosRec records a selected display to an H.264 MP4 file, optionally adding microphone audio and a camera overlay. It uses native AppKit and AVFoundation instead of a browser engine, and includes low-load settings for Intel Macs that cannot run modern recording applications.

## Download

Download the latest installer from **[GitHub Releases](../../releases/latest)**:

1. Download `MaosRec-macOS-10.15-Intel.dmg`.
2. Open the DMG.
3. Drag **MaosRec.app** onto the **Applications** shortcut.
4. Open Applications, right-click MaosRec, and choose **Open** on first launch.
5. Allow Screen Recording and, when used, Camera and Microphone access.

Requirements:

- macOS Catalina 10.15 or newer;
- Intel (`x86_64`) Mac.

## Features

- Native, compact AppKit interface inspired by OBS source controls;
- selected-display recording to H.264 MP4;
- optional microphone or virtual audio-device recording;
- camera overlay with adjustable size and four corner positions;
- Economy 540p/12 fps mode for Macs with very limited CPU and memory;
- Balanced 720p/15 fps and Smooth 720p/30 fps modes;
- English, Russian, or automatic system language;
- automatic system light or dark appearance;
- configurable recordings folder;
- update notification, download, SHA-256 verification, installation, and relaunch;
- automated Intel DMG and ZIP releases through GitHub Actions.

macOS 10.15 does not provide ordinary applications with direct system-audio capture. MaosRec records the selected audio input. A virtual audio device can be selected when application audio is required.

## Documentation

- [English user guide](README.en.md)
- [Русское руководство](README.ru.md)

## Build from source

GitHub Actions builds the Catalina-compatible Intel app automatically. On a Mac with Xcode installed:

```bash
bash Scripts/package.sh
```

The command creates:

- `dist/MaosRec-macOS-10.15-Intel.dmg`;
- `dist/MaosRec-macOS-10.15-Intel.zip`;
- `dist/SHA256SUMS.txt`.

To publish a release, push a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds the app and adds all three files to GitHub Releases. No update-signing secrets are required. Public packages are ad-hoc signed, so macOS may require right-click → **Open** on first launch.

## License

MaosRec is available under the [MIT License](LICENSE).
