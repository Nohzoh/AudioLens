#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p coverage
flutter test --coverage test/location_info_test.dart test/guide_error_test.dart
lcov --summary coverage/lcov.info >/dev/null 2>&1 || true
open coverage/html/index.html 2>/dev/null || true
