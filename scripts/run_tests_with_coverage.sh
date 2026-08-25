#!/usr/bin/env bash
# #140: runs the full test suite with coverage and checks it against the
# same floor CI enforces (scripts/check_coverage.py) — was previously
# scoped to just 2 test files, from back when T105 added the first
# widget-level tests; the full suite has grown a lot since.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test --coverage
python3 scripts/check_coverage.py

if command -v genhtml >/dev/null 2>&1; then
  genhtml coverage/lcov.info -o coverage/html >/dev/null
  open coverage/html/index.html 2>/dev/null || true
else
  echo "(genhtml not installed — skipping HTML report; brew install lcov for one)"
fi
