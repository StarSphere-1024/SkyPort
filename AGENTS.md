# AGENTS.md

## Scope and Navigation

SkyPort is a Rust + Flutter serial-port debugging assistant. Current targets are Windows and Linux desktop; macOS project files do not imply support.

Read additional context only when relevant:

- `PRODUCT.md`: product behavior, UX priorities, and supported versus planned platforms.
- `README.md`: setup, running, building, packaging, and bridge-generator installation.
- `docs/rust-serial-kernel-design.md`: core contracts, especially “已落地的核心合同与验证入口”; historical migration sections are not the current implementation map.
- `app/pubspec.yaml`: app version, Dart SDK constraints, and Flutter dependencies. Cargo manifests/`Cargo.lock`: Rust dependencies; the bridge manifest pins the FRB version.
- `.github/workflows/`: actual CI checks and platform packaging steps.

- Modify README files only when explicitly requested or to minimally correct existing errors; new features alone do not justify changes. Keep implementation and verification notes in chat.
- When updating README images, replace only the referenced image assets by default, using screenshots of the actual current UI.
- Unless explicitly requested, update docs only when existing guidance becomes incorrect; do not create documentation files unless requested.
- Keep instructions and replies concise; amend existing rules instead of adding repetitive lists.
- Before implementation, state the understood requirements and approach. Confirm unresolved behavior or visual choices with the user before editing; assumptions are not agreement.
- Do not add UI copy that merely repeats a title or control label; helper text must provide necessary additional information.

Key implementation entry points:

| Path | Responsibility |
| --- | --- |
| `crates/skyport_core/src/` | Independent backend: lifecycle, serial I/O, configuration, logs/export, statistics, scheduling |
| `crates/skyport_flutter_bridge/src/api.rs` | Flutter adapter API and type conversion |
| `app/lib/host_core.dart` | Native loading, bootstrap, legacy migration, awaited host shutdown |
| `app/lib/providers/ui_controller.dart` | User intents, command outcomes, event consumption, UI projection |
| `scripts/rust.cmake` | Cargo build and native library bundling for Linux/Windows runners |

## Architecture Invariants

- Keep `skyport_core` independent of Flutter, Dart, and FRB; the bridge depends on the core, never the reverse.
- Rust owns serial lifecycle/validation, text/Hex encoding and newline handling, reconnect/auto-send scheduling, serial configuration persistence, logs/export, and statistics. Do not duplicate these rules in Dart or the bridge.
- Widgets render neutral `UiState` and send intents through `UiController`. Dart owns frontend settings, drafts, display/ANSI rendering, and state projection, not serial state machines.
- The host creates and explicitly awaits closing the core. Widget/provider disposal cancels subscriptions only; preserve the native close-request handshake and background work.
- Subscribe atomically with the initial snapshot, then apply events in sequence. Keep queues bounded; report overflow/data gaps and recover with a fresh atomic subscription. Recovery does not restore lost data.
- Request acceptance is not command completion or successful transmission. Preserve final outcomes and bytes written on partial failure.
- Preserve transport bytes: no hidden retries, silent Hex correction, or implicit resend after partial writes. Configured reconnection after connection loss must remain visible and testable.
- Rust persists serial preferences in versioned `config.json`; `shared_preferences` stores frontend preferences and supplies legacy migration input. Mark migration complete only after successful core persistence.
- Keep log truncation/data gaps visible. UI preview clipping must not change retained/exported bytes. Localize structured core errors in the frontend, not in the core.
- Update all affected consumers when changing core/bridge types, event semantics, or persistence contracts.

## Working Directories and Generation

- Use repository-relative paths and SDKs from `PATH`; do not commit machine-specific paths.
- Run Cargo and repository helper scripts from the root; run Flutter/Dart package and generation commands from `app/`.
- Use `tool/test_quiet.sh` for Flutter tests; it switches to `app/` and forwards arguments. `DART_BIN`/`FLUTTER_BIN` override the binaries. Without Bash, run `dart ../tool/quiet_flutter_test.dart` from `app/`. Direct `flutter test` is reserved for debugging/changing the wrapper.
- Only regenerate when the relevant sources/configuration change; generation is not a routine validation step:
  - Localization: update both `app/lib/l10n/app_en.arb` and `app/lib/l10n/app_zh.arb`; run `flutter gen-l10n` from `app/`.
  - Bridge: edit the API/core types, use the generator version pinned by `crates/skyport_flutter_bridge/Cargo.toml`, then run `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` from `app/`.
- Never hand-edit generated `app_localizations*.dart`, `app/lib/src/rust/`, or `crates/skyport_flutter_bridge/src/frb_generated.rs`.
- Use `dart format --output=none --set-exit-if-changed` to check formatting; use `dart format` only to format changed Dart files.

## Verification by Change

Apply every relevant row for cross-layer changes, not every check for every task.

| Change | Required verification |
| --- | --- |
| Documentation only | Check affected paths, command arguments, and referenced configuration; no full test suite by default |
| Rust core | `cargo test --locked -p skyport_core` from root; serial changes need Linux PTY coverage in the core runtime tests |
| Dart UI/state projection | `flutter analyze` from `app/` and affected unit/widget tests through the wrapper; observe the running UI for visual changes |
| Bridge/host lifecycle | Core and affected Dart checks, plus `python3 scripts/pty_ui_smoke.py` from root for real Linux UI/bridge integration |
| Build/packaging | Build on the target host and run `python3 scripts/package_smoke.py <artifact>` from root against the actual bundle/package |

- Linux UI/package smoke needs a display; prefix with `xvfb-run -a` when headless. Build/bundle details and supported package formats are in `README.md`.
- Common targeted Flutter invocation: `tool/test_quiet.sh test/ansi_test.dart` from root. Add `--coverage` when coverage is relevant; check with `scripts/check_coverage.sh` or `scripts/check_coverage.ps1`.
- Dart tests belong in `app/test/unit/`, `app/test/widget/`, `app/test/helpers/`, and `app/integration_test/`. Mock the UI state/intent boundary, not native sessions; use real integration for native behavior.
- Core tests under `crates/skyport_core/tests/` use Linux pseudo-terminals, not physical hardware. Test behavior, boundaries, transitions, transport errors/bytes, persistence, and lifecycle—not default wording or incidental formatting.
- Report checks actually executed and identify unverified items. Analysis/compilation does not prove native loading; Linux smoke does not establish Windows, another architecture, or electrical hardware correctness. Missing display/platform/hardware must be reported, not replaced with an unsupported success claim.
