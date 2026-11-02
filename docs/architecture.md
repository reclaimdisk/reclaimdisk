# Architecture

ReclaimDisk is one Swift package. The domain follows domain-driven design where the rules live, and CI checks the boundaries mechanically. This page describes what exists in the code today.

## Targets and allowed dependencies

`architecture/allowed-dependencies.json` is the source of truth; CI fails on any other edge.

| Target | Role | Depends on |
|---|---|---|
| SharedKernel | ByteCount, CanonicalPath, Instant, Kind, ReclaimClass, Target | — |
| Inventory | Scan, Node, NodeDraft, Footprint, KindTotal, VolumeCapacity, DiskLayout, UnreadableArea, KindClassifier | SharedKernel |
| Catalog | Candidate, evidence, estimates, and the scan rules (Rust build folders, Node dependencies, JavaScript build caches, Python environments) | SharedKernel |
| Cleanup, Ledger | Empty namespaces until cleaning and its record arrive | SharedKernel |
| Application | Ports, scanning (ScanBuilder, ReadPool, Folding, LinkAndCloneAccounting), RunScan, ScanCatalogQuery, ProposeCandidates, UserMessages, ByteFormatting, KindTitles, DisplayText, ProductInfo | SharedKernel + the four contexts |
| Infrastructure | DarwinVolumeReader (getattrlistbulk, lstat, statfs, getattrlist), PathResolver (realpath), SystemWallClock, LiveCatalog | SharedKernel, Inventory, Catalog, Application |
| CLI | `reclaimdisk scan`, `reclaimdisk candidates` and `--version` (swift-argument-parser) | SharedKernel, Inventory, Catalog, Application, Infrastructure, ArgumentParser |
| AppFeature | ScanModel, DiskBarModel, KindPalette, LockedFolders, `Node.displayName`, treemap layout and views | SharedKernel, Inventory, Catalog, Application, Infrastructure |
| ReclaimDiskApp | `@main` only | AppFeature |
| TestSupport | FakeVolumeReader, FakeClock, test builders (test targets only) | SharedKernel, Inventory, Catalog, Application |

## Where DDD applies

- **Domain targets** (SharedKernel, Inventory, Catalog, Cleanup, Ledger) import only the standard library and their allowed targets, declare no build settings, and aren't `Codable`. CI enforces all three (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- **Inventory is a read model.** A `Scan` is an immutable value built once. `Scan.init` is the only place nodes are validated:
  - every total keeps "frees at least" ≤ "takes up";
  - kinds are assigned top-down by `KindClassifier`.
- **Contexts meet only in Application.** The scanner produces `NodeDraft`s; `RunScan` turns them into a `Scan`.
- **Not DDD, by design:** the folder walk (`ScanBuilder`, `DirectoryTable`, `Folding`), the treemap layout, CLI formatting and the adapters.

## Ports

| Port | Declared in | Implemented by |
|---|---|---|
| `VolumeReader` (readDirectory, entryType, deviceID, mountPath, capacity) | Application | `DarwinVolumeReader`; `FakeVolumeReader` in tests |
| `WallClock` | Application | `SystemWallClock`; `FakeClock` in tests |
| `ScanQuery` (folders of a finished scan) | Catalog | `ScanCatalogQuery` |

## Scanning, in order

1. **RunScan** reads the disk layout (each volume's own use from `getattrlist` `ATTR_VOL_SPACEUSED`; on APFS, `statfs` reports the whole container's use for every volume) and checks a `--path` folder: it exists, is a directory, and is mounted on the Data volume (the System volume shares its device id, so the mount decides).
2. **ScanBuilder** walks breadth-first:
   - at most `maxConcurrentReads` reads in flight;
   - every blocking call goes through `ReadPool` (a private concurrent DispatchQueue), never Swift's cooperative pool;
   - it never descends into mount points, other devices or symlinks;
   - `DarwinVolumeReader` retries a read interrupted with EINTR, and turns off downloading cloud-only (dataless) files for the process, so such folders fail at once and count as zero.
3. **DirectoryTable** keeps one compact row per folder plus large files (≥ 0.25 GiB), never every file. Two kinds of marker are recorded on a folder: force-kept names (`CACHEDIR.TAG`, `.rustc_info.json`) and project files (package.json, lockfiles, `pyvenv.cfg`, `Cargo.toml`, and the Gradle build files). Only the force-kept names keep a folder. Dependency and cache directories (`node_modules`, `.next`, `.turbo`, `.parcel-cache`, `.svelte-kit`, `.nuxt`, `.venv`, `venv`) are kept when their total is at least 1 MiB and no ancestor below the scan root already has one of those names or a force-kept marker.
4. **LinkAndCloneAccounting:**
   - a hard-linked inode counts once, in the folder of its first path;
   - its private bytes count only when every link was found, as a credit that Folding places on the smallest node holding every link;
   - full clone groups count once in `scannedUniqueBytes`.
5. **Folding** classifies every folder and keeps the big or notable ones. The rest fold into one aggregate per Kind under their kept parent.
6. **Scan.init** validates and assigns kinds. `notReadable` = Data volume used − scanned unique bytes.
7. **ProposeCandidates** reads that scan through `ScanCatalogQuery` and runs the catalog rules off the cooperative pool. It drops path candidates inside personal folders, keeps one candidate per id, and can filter by kind.

## Front ends

- **CLI:** `reclaimdisk scan [--path <folder>] [--json]` and `reclaimdisk candidates [--path <folder>] [--kind <kind>] [--json]`. Text output or JSON schema 1; exit 0 on success and 1 on any error (its own `main`, because swift-argument-parser would exit 64). `candidates` lists proposals and deletes nothing.
- **App:** an Overview tab (disk bar, key, Full Disk Access notice) and a Map tab (nested treemap up to three levels, breadcrumbs, a side list that is also the VoiceOver form). `ScanModel` drives both.
