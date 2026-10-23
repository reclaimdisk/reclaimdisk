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

# End-to-end: exact numbers for a real folder.
bin="$(swift build --show-bin-path)/reclaimdisk"
tmp=$(mktemp -d)
head -c 1048576 /dev/urandom > "$tmp/plain"
head -c 1048576 /dev/urandom > "$tmp/hl" && ln "$tmp/hl" "$tmp/hl2"
head -c 1048576 /dev/urandom > "$tmp/orig" && cp -c "$tmp/orig" "$tmp/clone"
sync
"$bin" scan --path "$tmp" --json > "$tmp.json"
# takesUp 4 MiB (plain + hard link once + two clones), freesAtLeast 2 MiB (plain + hard link), unique 3 MiB
swift scripts/check-scan-json.swift "$tmp.json" 4194304 2097152 3145728
rc=0; "$bin" scan --path /etc/hosts 2> "$tmp.err" || rc=$?
[ "$rc" -eq 1 ] && grep -q "is not a folder" "$tmp.err" || { cat "$tmp.err" >&2; echo "expected exit 1 for a file path" >&2; exit 1; }
rc=0; "$bin" scan --no-such-flag 2> /dev/null || rc=$?
[ "$rc" -eq 1 ] || { echo "usage errors must exit 1, got $rc" >&2; exit 1; }
rm -rf "$tmp" "$tmp.json" "$tmp.err"
echo "end-to-end: ok"
