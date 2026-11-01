#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
abis=${SKYPORT_ANDROID_ABIS:-arm64-v8a}
export PATH="${HOME}/.cargo/bin:$PATH"
sdk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [[ -z "$sdk" ]]; then
  android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
  [[ -n "$android_sdk" ]] || { printf 'Set ANDROID_HOME or ANDROID_SDK_ROOT.\n' >&2; exit 1; }
  if [[ -n "${SKYPORT_ANDROID_NDK_VERSION:-}" ]]; then
    sdk="$android_sdk/ndk/$SKYPORT_ANDROID_NDK_VERSION"
  else
    version=$(find "$android_sdk/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
    sdk="$android_sdk/ndk/$version"
  fi
  [[ -d "$sdk" ]] || { printf 'Android NDK not found: %s\n' "$sdk" >&2; exit 1; }
fi
prebuilt=("$sdk"/toolchains/llvm/prebuilt/*/bin)
[[ ${#prebuilt[@]} -eq 1 && -d "${prebuilt[0]}" ]] || {
  printf 'Cannot locate the Android NDK host toolchain.\n' >&2; exit 1;
}
toolchain=${prebuilt[0]}
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C link-arg=-Wl,-z,max-page-size=16384"

cd "$root"
for abi in ${abis//,/ }; do
  case "$abi" in
    arm64-v8a) target=aarch64-linux-android; clang=aarch64-linux-android26 ;;
    x86_64) target=x86_64-linux-android; clang=x86_64-linux-android26 ;;
    *) printf 'Unsupported Android ABI: %s\n' "$abi" >&2; exit 1 ;;
  esac
  linker_key="CARGO_TARGET_${target^^}_LINKER"
  linker_key=${linker_key//-/_}
  export "$linker_key=$toolchain/$clang-clang"
  export "CC_${target//-/_}=$toolchain/$clang-clang"
  export "AR_${target//-/_}=$toolchain/llvm-ar"
  cargo build --target "$target" --target-dir "$root/target/android" --release -p skyport_flutter_bridge --locked
  destination="$root/app/android/app/src/main/jniLibs/$abi"
  mkdir -p "$destination"
  cp "$root/target/android/$target/release/libskyport_flutter_bridge.so" "$destination/"
done
