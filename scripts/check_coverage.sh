#!/bin/bash

# Coverage Check Script for SkyPort
# Usage: ./scripts/check_coverage.sh [--threshold 70]

set -e

cd "$(dirname "$0")/.."

THRESHOLD=70
COVERAGE_FILE="coverage/lcov.info"

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

# Parse lcov.info and calculate coverage
TOTAL_LF=$(grep "^LF:" "$COVERAGE_FILE" | awk -F: '{sum+=$2} END {print sum}')
TOTAL_LH=$(grep "^LH:" "$COVERAGE_FILE" | awk -F: '{sum+=$2} END {print sum}')

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
