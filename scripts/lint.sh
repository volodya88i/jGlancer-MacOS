#!/usr/bin/env bash
# Lints App, Packages and scripts. Configuration: .swiftformat, .swiftlint.yml (and scripts/.swiftlint.yml).
# To apply formatting instead of checking it: swiftformat .
set -uo pipefail
cd "$(dirname "$0")/.."
if command -v swiftformat >/dev/null; then swiftformat . --lint || exit 1; else echo "swiftformat not installed (brew install swiftformat) — skipped"; fi
if command -v swiftlint   >/dev/null; then swiftlint lint --quiet --strict || exit 1; else echo "swiftlint not installed (brew install swiftlint) — skipped"; fi
