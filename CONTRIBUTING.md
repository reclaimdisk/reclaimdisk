# Contributing

Thanks for helping. ReclaimDisk is early: it scans and maps, and it doesn't delete anything yet. Reports with real numbers are especially useful: what the scan showed next to what `df` or Finder says for the same folder.

## Build and test

Requires macOS 14 or later and Xcode 26 (Swift 6.2). Run every check with:

```bash
scripts/ci.sh
```

It's the same script GitHub Actions runs (`.github/workflows/ci.yml`, `macos-26`). Please don't weaken a step to get it green; if a check is wrong, fix the check and say why.

## What each step proves

| Step | Proves |
|---|---|
| `check-architecture.swift self-test` | Each check fails on its planted violation, with its exact message (fixtures in `ArchitectureFixtures/`). It also proves comments and strings naming a banned attribute pass, and a long swiftc error log fails the check instead of hanging it. |
| `undeclared-import` fixture build | SwiftPM's `--explicit-target-dependency-import-check error` still rejects an undeclared target import. The build must fail and print "without declaring it a dependency". |
| `graph` | The package's target graph equals `architecture/allowed-dependencies.json` exactly. |
| `imports` | Domain targets import only their allowed targets: any form, including `internal import`, `;`-joined lines, `@_exported` on its own line and imports inside `#if` (the compiler pass runs with the debug and the release conditions of `swift build`). Comments and string text are ignored. If SwiftPM ever passes a new `-D` condition, add it to `buildConditions`. |
| `settings` | Domain targets declare no build settings (unsafe flags could load Foundation with no import). |
| `swift build` / `swift test` | Everything compiles and all tests pass, with the import check on. |
| End-to-end | A real temp folder (plain file, hard-link pair, clone pair) scans to exactly 4 MiB takes up, 2 MiB frees at least, 3 MiB unique. A file path and an unknown flag both exit 1. |

The rules behind these checks, and what each target is for, are in [docs/architecture.md](docs/architecture.md).

## Adding a target

1. Add it to `Package.swift`.
2. Add it to `architecture/allowed-dependencies.json` with its exact dependencies. A domain target also goes in `domainTargets`.
3. Regenerate `ArchitectureFixtures/describe-extra-edge.json` from the real graph, keeping the planted `Cleanup -> Inventory` edge:
   ```bash
   swift package describe --type json > /tmp/d.json
   ```
   Then set Cleanup's `target_dependencies` to `["Inventory", "SharedKernel"]` and keep only `name`, `type`, `path`, `target_dependencies` and `product_dependencies`.
4. Run `scripts/ci.sh`.

**TestSupport** is a library only test targets may depend on. The graph check keeps production targets away from it.

## Looking at the app without launching it

The rendering tests draw the Overview and the Map off-screen and fail if a render is blank. To also write PNGs:

```bash
RECLAIMDISK_SNAPSHOT_DIR=/tmp swift test --filter 'overviewRenders|mapRenders'
```

Interactions (clicks, Reveal in Finder, VoiceOver) still need a person at `swift run ReclaimDiskApp`.

## Commits and pull requests

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `fix:`, `feat:`, `test:`, `docs:`, `refactor:`, `ci:`, `chore:`.
- A bug fix comes with a test that fails without it.
- Run `scripts/ci.sh` before opening a pull request.

## License

ReclaimDisk is licensed under the [Apache License 2.0](LICENSE). Unless you state otherwise, contributions you submit are licensed under the same terms (section 5 of the license).
