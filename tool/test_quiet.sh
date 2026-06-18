#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "${script_dir}/../SkyPort" && pwd)"
dart_bin="${DART_BIN:-/home/star/env/flutter/bin/dart}"

cd "${app_dir}"
exec "${dart_bin}" "${script_dir}/quiet_flutter_test.dart" "$@"
