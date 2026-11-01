#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config=${SKYPORT_ANDROID_KEY_PROPERTIES:-${HOME}/.config/skyport/android/key.properties}

case "${1:-build}" in
  init-signing)
    if [[ -e "$config" ]]; then
      printf 'Signing config already exists: %s\n' "$config" >&2
      exit 1
    fi
    command -v keytool >/dev/null 2>&1 || { printf 'keytool is required (install a JDK).\n' >&2; exit 1; }
    mkdir -p "$(dirname "$config")"
    chmod 700 "$(dirname "$config")"
    keydir=$(dirname "$config")
    umask 077
    store="$keydir/skyport-release.jks"
    [[ ! -e "$store" ]] || { printf 'Refusing to overwrite existing keystore: %s\n' "$store" >&2; exit 1; }
    store_password=$(openssl rand -hex 32)
    key_password=$(openssl rand -hex 32)
    export SKYPORT_STORE_PASSWORD="$store_password" SKYPORT_KEY_PASSWORD="$key_password"
    keytool -genkeypair -noprompt -keystore "$store" -storetype JKS \
      -storepass:env SKYPORT_STORE_PASSWORD -keypass:env SKYPORT_KEY_PASSWORD \
      -alias skyport-release -keyalg RSA -keysize 4096 -validity 10000 \
      -dname "CN=SkyPort Local Release, OU=Android, O=SkyPort, C=US" >/dev/null
    {
      printf 'storeFile=%s\n' "$store"
      printf 'storePassword=%s\n' "$store_password"
      printf 'keyAlias=skyport-release\n'
      printf 'keyPassword=%s\n' "$key_password"
    } > "$config"
    chmod 600 "$config" "$store"
    unset store_password key_password SKYPORT_STORE_PASSWORD SKYPORT_KEY_PASSWORD
    printf 'Created private release signing config: %s\n' "$config"
    ;;
  build)
    [[ -f "$config" ]] || { printf 'Missing signing config; run scripts/android_release.sh init-signing.\n' >&2; exit 1; }
    export SKYPORT_ANDROID_KEY_PROPERTIES="$config"
    cd "$root/app"
    targets=()
    for abi in ${SKYPORT_ANDROID_ABIS:-arm64-v8a}; do
      for item in ${abi//,/ }; do
        case "$item" in
          arm64-v8a) targets+=(android-arm64) ;;
          x86_64) targets+=(android-x64) ;;
          *) printf 'Unsupported Android ABI: %s\n' "$item" >&2; exit 1 ;;
        esac
      done
    done
    printf -v platforms '%s,' "${targets[@]}"
    flutter build apk --release --target-platform "${platforms%,}"
    printf '%s\n' "$root/app/build/app/outputs/flutter-apk/app-release.apk"
    ;;
  *)
    printf 'Usage: %s [init-signing|build]\n' "$0" >&2
    exit 2
    ;;
esac
