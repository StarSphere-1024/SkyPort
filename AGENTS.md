# AGENTS.md

## Project Overview

SkyPort is a Flutter serial-port debugging assistant. It targets desktop workflows first and provides serial connection, terminal-style data display, logging, file import/export, and localized UI.

## Environment Setup

Flutter is installed at `/home/star/env/flutter/bin/flutter`.

If `flutter` or `dart` is not on PATH, use the full paths:

```bash
/home/star/env/flutter/bin/flutter <command>
/home/star/env/flutter/bin/dart <command>
```

Run repository-level helper scripts from the repository root:

```bash
cd /home/star/Projects/SkyPort
```

Run raw Flutter commands from the Flutter app directory:

```bash
cd /home/star/Projects/SkyPort/SkyPort
```

## Common Commands

### Development

```bash
flutter run -d linux
flutter devices
flutter run -d <device-id>
```

### Build

```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

### Testing

Use the quiet wrapper for test runs. Do not run `flutter test` directly unless debugging or changing the wrapper itself.

```bash
# Run all tests
tool/test_quiet.sh

# Run one test file
tool/test_quiet.sh test/ansi_test.dart

# Run with coverage
tool/test_quiet.sh --coverage
```

The wrapper forwards normal `flutter test` arguments and strips reporter options so it can consume `--machine` output itself.

### Code Quality

```bash
flutter analyze
dart format lib/ test/
dart format --output=none --set-exit-if-changed lib/ test/
```

### Dependency Management

```bash
flutter pub get
flutter pub add <package_name>
flutter pub outdated
```

## Project Structure

```text
/home/star/Projects/SkyPort/
├── AGENTS.md
├── tool/
│   ├── quiet_flutter_test.dart
│   └── test_quiet.sh
└── SkyPort/
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── providers/
    │   ├── services/
    │   ├── utils/
    │   ├── widgets/
    │   └── l10n/
    ├── test/
    │   ├── unit/
    │   ├── widget/
    │   └── helpers/
    ├── integration_test/
    └── pubspec.yaml
```

## Key Configuration

- Dart SDK: `>=3.4.1 <4.0.0`
- State management: Riverpod (`flutter_riverpod`)
- Serial I/O: `flutter_libserialport`
- Localization: Flutter generated l10n (`l10n.yaml`, `lib/l10n/`)
- Testing: `flutter_test`, `mocktail`, `integration_test`, `golden_toolkit`, `fake_async`

## Development Constraints

- Keep serial-port behavior deterministic: avoid hidden retries, silent data mutation, or UI-only fixes for transport bugs.
- Preserve existing provider/service boundaries; widgets should render state and delegate I/O to providers/services.
- Update localization files when adding user-visible strings.
- Keep tests focused on behavior and edge cases, not current default strings or incidental formatting.
