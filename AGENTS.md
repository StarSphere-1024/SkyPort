# AGENTS.md

## Project Overview

SkyPort is a Flutter serial-port debugging assistant. It targets desktop workflows first and provides serial connection, terminal-style data display, logging, file import/export, and localized UI.

## Repository Layout

Use paths relative to the repository root; do not assume a particular user's home directory.

```text
.
├── AGENTS.md
├── tool/
│   ├── quiet_flutter_test.dart
│   └── test_quiet.sh
├── scripts/
│   ├── check_coverage.sh
│   └── check_coverage.ps1
└── app/
    ├── lib/
    ├── test/
    ├── integration_test/
    ├── assets/
    ├── linux/
    ├── windows/
    ├── macos/
    ├── l10n.yaml
    └── pubspec.yaml
```

- Run repository helper scripts from the repository root.
- Run Flutter, Dart, and package commands from `app/`, unless a command below says otherwise.
- `app/pubspec.yaml` is the source of truth for SDK and dependency requirements.

## Environment Setup

Use `flutter` and `dart` from `PATH` when available. If they are not available, configure the local SDK without committing machine-specific paths:

```bash
export FLUTTER_ROOT=/path/to/flutter
export PATH="$FLUTTER_ROOT/bin:$PATH"
```

`tool/test_quiet.sh` accepts `FLUTTER_BIN=/path/to/flutter` and `DART_BIN=/path/to/dart` overrides; otherwise it uses the binaries on `PATH`.

## Common Commands

From the repository root:

```bash
# Run all tests
tool/test_quiet.sh

# Run one test file
tool/test_quiet.sh test/ansi_test.dart

# Run with coverage
tool/test_quiet.sh --coverage

# Check generated coverage against the default threshold
scripts/check_coverage.sh
```

From `app/`:

```bash
# Development
flutter run -d linux
flutter devices
flutter run -d <device-id>

# Static analysis and formatting
flutter analyze
dart format lib/ test/
dart format --output=none --set-exit-if-changed lib/ test/

# Dependencies
flutter pub get
flutter pub add <package_name>
flutter pub outdated
```

Build only on a host with the corresponding platform toolchain:

```bash
# Linux host
flutter build linux --release

# Windows host
flutter build windows --release

# macOS host
flutter build macos --release
```

The current supported desktop targets are Windows and Linux. The macOS project files exist, but macOS support must not be assumed without a corresponding platform check.

## Testing

- Use `tool/test_quiet.sh` as the normal test entry point. Run `flutter test` directly only when debugging or changing the wrapper.
- Unit tests belong under `test/unit/`; widget tests under `test/widget/`; shared helpers under `test/helpers/`; integration tests under `integration_test/`.
- Integration tests may require a suitable Flutter device and platform setup.
- Test behavior and edge cases, not default strings or incidental formatting.
- Mock the UI state/intent boundary in unit and widget tests, not native sessions. Rust serial integration checks use Linux pseudo-terminals; do not require physical hardware for deterministic tests.

## Key Configuration

- Dart SDK: `>=3.10.0 <4.0.0`
- State management: Riverpod (`flutter_riverpod`)
- Serial I/O: independent `skyport_core` (`serialport`) with a separate `flutter_rust_bridge` adapter
- Dependency versions: `app/pubspec.yaml` and the Cargo workspace manifests/lockfile
- Localization source: `app/lib/l10n/*.arb`
- Generated localization output: `app/lib/l10n/app_localizations*.dart`
- Testing: `flutter_test`, `mocktail`, `integration_test`, `fake_async`

## Development Constraints

- Keep serial-port behavior deterministic: do not add hidden retries or silently mutate transport data. User-configured or explicitly visible automatic reconnection is allowed and must remain observable and testable.
- Widgets render neutral UI state and send user intents through the UI controller. Rust owns serial lifecycle, validation, persistence, logs, statistics, and scheduling; Dart providers only project core state or hold frontend-only settings.
- When adding user-visible strings, update the relevant `.arb` source files and regenerate localization output; do not edit generated localization Dart files by hand.
- Keep tests focused on behavior, edge cases, state transitions, and transport errors.
- From the repository root, run `cargo test --locked -p skyport_core` without Flutter. For real Linux UI/bridge verification use `python3 scripts/pty_ui_smoke.py`; for final bundles/packages use `python3 scripts/package_smoke.py <artifact>` with a suitable desktop display.
