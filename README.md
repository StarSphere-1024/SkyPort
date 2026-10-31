<div align="center">

<img src="app/assets/icon.png" alt="SkyPort" width="88">

# SkyPort

**English** · [简体中文](README_zh_CN.md)

**A cross-platform desktop serial port debugging assistant built with Flutter and Rust**

Connect devices, send and receive text or Hex data, inspect ANSI-colored logs, and export debugging records.

[![CI](https://github.com/StarSphere-1024/SkyPort/actions/workflows/ci.yml/badge.svg)](https://github.com/StarSphere-1024/SkyPort/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/StarSphere-1024/SkyPort)](https://github.com/StarSphere-1024/SkyPort/releases/latest) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

[Download](#download) · [Quick start](#quick-start) · [Release notes](https://github.com/StarSphere-1024/SkyPort/releases) · [Build from source](#build-from-source) · [Report an issue](#report-an-issue)

**Windows / Linux** · **Text / Hex** transfer · **English / Chinese** interface

</div>

<p align="center">
  <img src="static/images/main_interface.png" alt="SkyPort dark theme with a Chinese interface and deterministic demo data: serial settings, text transmission, and ANSI-colored logs" width="100%">
</p>

## Features

- **Serial connections**: discover available ports, configure baud rate, data bits, stop bits, parity, and flow control, and remember your settings.
- **Text and Hex transfer**: switch transmission and receive-display modes; optionally append LF, CR, or CRLF to text transmissions.
- **Log viewing and export**: display ANSI colors, timestamps, and separate sent and received records; adjust the log buffer and export debugging records.
- **Repeatable debugging**: reduce repetitive input with send history and automatic sending at a configurable interval.
- **Connection status and statistics**: view connection state, byte counts, and receive rate, with optional automatic reconnection after a device disconnects.
- **Desktop experience**: English and Chinese interfaces, light, dark, and system themes, and remembered window size and position.

## Download

Download from the **[latest release](https://github.com/StarSphere-1024/SkyPort/releases/latest)**. Previous versions and release notes are available on [Releases](https://github.com/StarSphere-1024/SkyPort/releases).

| Platform | Packages | How to choose |
| --- | --- | --- |
| Windows | Installer `-setup.exe` / portable `-portable.zip` | Follow the installer, or fully extract the portable archive and run `skyport.exe` |
| Linux | `.deb` / `.rpm` / `.AppImage` | Prefer `.deb` on Debian / Ubuntu, `.rpm` on RPM-based distributions such as Fedora, or make the AppImage executable and run it |

Both platforms provide `amd64` (x64 / x86_64) and `arm64` (ARM64 / aarch64) packages. Choose `amd64` for Intel / AMD x64 computers and `arm64` for ARM devices. Check your system's processor architecture if unsure.

> Keep the entire portable directory intact. Do not copy only the executable or remove bundled libraries and resources. Windows and Linux are currently supported; macOS is not. The macOS project files in this repository do not imply a supported release.

## Quick start

1. **Connect your device**: plug the serial device into your computer, launch SkyPort, and select a port under "Serial Port Settings".
2. **Match the parameters**: set baud rate, data bits, stop bits, parity, and flow control to match your device. Click "Connect" and confirm that the status becomes "Connected".
3. **Send data**: enter a command supported by your device. In text mode, configure newline handling to match its protocol. For binary data, enable "Hex Send" and enter complete bytes.
4. **Inspect the response**: view sent and received records in the log area. Enable Hex display, timestamps, or ANSI rendering as needed. Whether the device echoes or responds depends on its protocol.
5. **Save your records**: use "Export Logs" to save debugging records. To send the same content repeatedly, configure an automatic-send interval.

Automatic reconnection restores the connection; it does not mean failed data has been resent. If sending fails, inspect the error and the number of bytes written before deciding what to do next.

## FAQ

**No serial port found, or unable to connect?**

Check that the operating system recognizes the device, the required drivers are installed, and no other program is using the port. On Linux, also check your user's permissions for the serial device. Do not bypass permission setup by routinely running the application as root.

**Garbled received data, or no response after sending?**

Check the communication parameters, text / Hex mode, and newline requirements. Inspect binary data using Hex display. ANSI rendering is for text logs containing escape sequences; it does not turn binary data into readable text.

**Can exported logs recover lost data?**

No. Exports contain only the records currently retained. Data evicted from the buffer or lost in a data gap cannot be recovered by exporting. Export important debugging records promptly.

## Build from source

### Prerequisites

- Flutter / Dart: satisfy the SDK constraints in [`app/pubspec.yaml`](app/pubspec.yaml). See the [CI configuration](.github/workflows/test.yml) for the toolchain versions used in CI.
- Rust stable, with the appropriate platform compilation target installed through rustup.
- Windows: Visual Studio with the "Desktop development with C++" workload.
- Linux: Clang, CMake, Ninja, `pkg-config`, and GTK3 and libudev development packages. On Debian / Ubuntu:

  ```bash
  sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libudev-dev
  ```

Running only the Rust core tests does not require Flutter. On Linux, `pkg-config` and the libudev development package are still required.

### Get the source and dependencies

```bash
git clone https://github.com/StarSphere-1024/SkyPort.git
cd SkyPort
cd app
flutter pub get
```

### Run and build

Run the following commands from `app/`, choosing the group for your host system:

**Windows**

```bash
flutter run -d windows
flutter build windows --release
```

**Linux**

```bash
flutter run -d linux
flutter build linux --release
```

Flutter's Windows / Linux CMake build invokes Cargo and bundles the Rust bridge library. Distribute the complete bundle: `skyport_flutter_bridge.dll` sits next to the Windows `.exe`, while Linux uses `lib/libskyport_flutter_bridge.so`.

## Development and contributing

SkyPort uses Rust + Flutter. The independent Rust core owns serial lifecycle, data transfer, configuration persistence, logs, statistics, and scheduling. Flutter handles the desktop interface and interaction, accessing the core through `flutter_rust_bridge`.

See the [Rust core design](docs/rust-serial-kernel-design.md) (in Chinese) for architecture and data, queue, and configuration migration contracts. Dependency versions are defined in the [Flutter manifest](app/pubspec.yaml), [Cargo manifest](Cargo.toml), and their respective lockfiles.

When opening a pull request, describe the use case, behavior changes, and verification results. Include reproduction steps for bug fixes. When changing cross-layer interfaces, update Rust, the bridge, and Dart consumers together.

<details>
<summary>Local checks and real serial-path verification</summary>

Run the Rust core tests and Flutter unit / widget tests from the repository root:

```bash
cargo test --locked -p skyport_core
tool/test_quiet.sh
```

On systems without Bash, such as Windows, run `dart ../tool/quiet_flutter_test.dart` from `app/`. Run static analysis from `app/` as well:

```bash
flutter analyze
```

Run the following commands from the repository root:

```bash
python3 scripts/pty_ui_smoke.py
python3 scripts/package_smoke.py <bundle-or-package-path>
```

- `pty_ui_smoke.py`: Linux only; exercises data transfer and lifecycle with the real UI, bridge, and pseudo-terminals.
- `package_smoke.py`: checks loading and lifecycle for a complete bundle, deb, rpm, AppImage, or Windows portable zip on the corresponding platform. Install Windows installers into an isolated directory first, then check that directory.
- Linux checks require a display. Prefix commands with `xvfb-run -a` in headless environments.
- RPM package checks require `bsdtar`; install `libarchive-tools` on Debian / Ubuntu.
- On Windows, replace `python3` with your local Python command, usually `python`.

Pseudo-terminal verification does not replace acceptance testing with physical serial ports, other architectures, or actual hardware.

</details>

<details>
<summary>Generate bindings after changing the bridge API</summary>

Regenerate bindings only after relevant API / type changes. Do not edit generated files manually. Keep the generator version aligned with the [bridge manifest](crates/skyport_flutter_bridge/Cargo.toml).

Run from the repository root:

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cd app
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

</details>

## Report an issue

Report bugs or suggest features through [GitHub Issues](https://github.com/StarSphere-1024/SkyPort/issues). Search existing issues first, and include where possible:

- Application version, operating system version, and processor architecture.
- Reproduction steps, expected behavior, and actual results.
- Relevant serial parameters, text / Hex mode, and newline configuration.
- Error messages, diagnostic details, relevant logs, or screenshots.

Remove keys, device identifiers, and other sensitive data before sharing logs. For feature requests, describe the debugging scenario and the problem you want to solve.

## License

SkyPort is licensed under the [GNU Affero General Public License v3.0](LICENSE).

Maintained by [StarSphere-1024](https://github.com/StarSphere-1024).
