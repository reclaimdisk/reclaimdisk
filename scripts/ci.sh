#!/usr/bin/env bash
# The single CI entry point (local and GitHub Actions). Every step must pass; never weaken one to get green.
set -euo pipefail
cd "$(dirname "$0")/.."

swift --version
swift scripts/check-architecture.swift self-test

# Expected failure: the planted undeclared import must make the build fail AND print the import-check message.
if out=$(cd ArchitectureFixtures/undeclared-import && swift build --explicit-target-dependency-import-check error 2>&1); then
  echo "undeclared-import fixture built; the import check is not working" >&2; exit 1
fi
grep -q "without declaring it a dependency" <<<"$out" || { echo "$out" >&2; echo "fixture failed for another reason" >&2; exit 1; }
echo "undeclared-import fixture: rejected as expected"

mkdir -p .build
swift package describe --type json > .build/describe.json
swift package dump-package > .build/dump.json
swift scripts/check-architecture.swift graph architecture/allowed-dependencies.json .build/describe.json
swift scripts/check-architecture.swift imports architecture/allowed-dependencies.json .build/describe.json .
swift scripts/check-architecture.swift settings architecture/allowed-dependencies.json .build/dump.json

swift build --explicit-target-dependency-import-check error
swift test --explicit-target-dependency-import-check error
