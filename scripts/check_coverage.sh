#!/bin/bash

# Coverage Check Script for SkyPort
# Usage: ./scripts/check_coverage.sh [--threshold 70]

set -e

cd "$(dirname "$0")/.."

THRESHOLD=70
COVERAGE_FILE="SkyPort/coverage/lcov.info"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if coverage file exists
if [ ! -f "$COVERAGE_FILE" ]; then
  echo "❌ Coverage file not found: $COVERAGE_FILE"
  echo "Run 'flutter test --coverage' first"
  exit 1
fi

# Parse lcov.info and calculate coverage. Keep this aligned with CI by
# excluding generated localization files.
TOTALS=$(awk '
  /^SF:lib[\/\\]l10n[\/\\]app_localizations(_.*)?\.dart$/ { skip=1; next }
  /^SF:/ { skip=0 }
  !skip && /^LF:/ { split($0, a, ":"); lf += a[2] }
  !skip && /^LH:/ { split($0, a, ":"); lh += a[2] }
  END { print lf " " lh }
' "$COVERAGE_FILE")
read -r TOTAL_LF TOTAL_LH <<< "$TOTALS"

if [ "$TOTAL_LF" -eq 0 ]; then
  echo "❌ No coverage data found"
  exit 1
fi

COVERAGE_PCT=$((TOTAL_LH * 100 / TOTAL_LF))

echo "================================"
echo "   SkyPort Coverage Report"
echo "================================"
echo "Lines Hit:    $TOTAL_LH"
echo "Lines Found:  $TOTAL_LF"
echo "Coverage:     ${COVERAGE_PCT}%"
echo "Threshold:    ${THRESHOLD}%"
echo "================================"

if [ "$COVERAGE_PCT" -lt "$THRESHOLD" ]; then
  echo "❌ FAILED: Coverage ${COVERAGE_PCT}% is below threshold ${THRESHOLD}%"
  exit 1
else
  echo "✅ PASSED: Coverage ${COVERAGE_PCT}% meets threshold ${THRESHOLD}%"
  exit 0
fi
