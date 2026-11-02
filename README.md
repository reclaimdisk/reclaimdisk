# ReclaimDisk

**The Mac disk cleaner that shows its work.** ReclaimDisk is for developers whose disks fill up with build output, caches, Docker, simulators and AI-agent worktrees.

- **Real numbers.** Every folder shows two sizes:
  - **takes up**, what it occupies;
  - **frees at least**, what deleting it would certainly give back.

  Copies that share blocks (APFS clones) and hard links aren't counted twice.
- **Nothing in use gets touched.** That matters once cleaning arrives: anything that can't be verified counts as in use.
- **It knows developer tools.** Build folders are recognized by their markers (for example Cargo's `CACHEDIR.TAG` + `.rustc_info.json`, whatever the folder is called), and each folder is sorted into a kind.

> **Status: work in progress.** This version scans, maps, and lists cleanup candidates. It never deletes anything.

## Build and run

Requires macOS 14 or later and Xcode 26 (Swift 6.2).

```bash
swift build -c release
.build/release/reclaimdisk scan                  # whole Data volume
.build/release/reclaimdisk scan --path ~/Projects
.build/release/reclaimdisk scan --path . --json  # JSON schema 1
.build/release/reclaimdisk candidates --path ~/Projects
.build/release/reclaimdisk candidates --path . --json
swift run ReclaimDiskApp                         # the app: Overview and Map
scripts/ci.sh                                    # all checks
```

## Honest limits

- **Read-only** in this version. `candidates` only lists what a later cleanup could remove, and a folder changed in the last 24 hours stays visible but is not preselected.
- **"Frees at least" is a lower bound.** Blocks shared only between files you'd delete together aren't credited yet.
- **Locked folders.** Some folders (Mail, Messages, Safari) need Full Disk Access to be counted: System Settings › Privacy & Security › Full Disk Access.
- **"Not counted" space.** System-only folders, file-system metadata and snapshots stay uncounted, and the app shows them as "Not counted".
- **Cloud-only folders count as zero.** Folders whose contents live only in iCloud, Google Drive or another cloud provider take no space on the Mac, and the scan never downloads them.

## Credits

Ideas, not code, from:

- **[Mole](https://github.com/tw93/Mole):** in-use checks, and refusing when unsure.
- **[dua-cli](https://github.com/Byron/dua-cli):** counting fully shared APFS clones once.
- **[kondo](https://github.com/tbillington/kondo) and [npkill](https://github.com/voidcosmos/npkill):** project-type build artifacts.
- **[GrandPerspective](https://grandperspectiv.sourceforge.net/) and Disk Inventory X:** the treemap.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, the checks and how the code is laid out ([docs/architecture.md](docs/architecture.md)).

## License

[Apache License 2.0](LICENSE).
