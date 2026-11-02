# candidates: ReclaimDisk lists what could go (read-only catalog, `reclaimdisk candidates`, the Cleanup screen)

2026-11-02 · keryx run `candidates`

## Proof
- Acceptance check:
  Live, on the owner's Mac, scripted in `<state>/qa/live-acceptance.py`: `reclaimdisk candidates --json` over the whole Data
  volume lists, each with evidence: a Rust build folder in a worktree (including a custom-named one such as `.worktrees/_target`);
  build output inside a temp folder of an ended agent session; the Docker build cache with the disk file's allocated size
  against its maximum; simulator download leftovers as report only when present; Playwright builds no project references when
  present. It lists nothing under personal folders (Documents, Desktop, Downloads, Pictures, Movies, Music, Mail, Messages,
  iCloud Drive, CloudStorage) and nothing git-tracked.
  On the base (7d83753): `reclaimdisk candidates` → `Error: Unexpected argument 'candidates'`, exit 1.
  At the final code: 0 failing checks over 207 candidates (and 0 over 284 before the review fixes narrowed the scan rules).
  Plus manual QA of the Cleanup screen in the app, with screenshots in `<state>/qa/QA.md`.
- Fresh review: `.keryx/runs/candidates/review/7d83753de8b0..e1ff32e33831.findings.md`: P0 0 · P1 1 · P2 7 · P3 0, all fixed
- Second finder: `.keryx/runs/candidates/review/7d83753de8b0..e1ff32e33831.security.findings.md`: P0 0 · P1 0 · P2 3 · P3 1;
  two P2 fixed, one ruled (see Rulings), the P3 deferred
- QA: `.keryx/runs/candidates/qa/QA.md` (kept where the run ran, not committed)
- CI: `scripts/ci.sh` at the shipped head, 242 tests, `end-to-end: ok`.
- Mutation probes on every slice; each survivor got a test that now catches it. The stale-object estimate matched an
  independent walk of the same folder to the byte.

## What changed
- `reclaimdisk candidates [--path <folder>] [--kind <kind>] [--json]` lists cleanup candidates with evidence, recovery and an
  honest estimate. A folder run lists only candidates inside that folder.
- The app has a Cleanup tab for a finished scan: grouped candidates, what is selected by default, blocked rows with what to do,
  report-only rows with why. Nothing is deleted and there is no Clean button.
- Rule groups: scan rules, tool caches (Docker, package managers), agent sessions and worktrees, runtimes (Xcode, simulators,
  Android) and apps (Playwright builds, app caches). Readers run read-only queries with timeouts.
- Branch `feat/candidates`, one pull request for the owner to merge.

## Open
- Not verified: the whole flow on a second Mac; the app as a bundle (it ran unbundled, so macOS asked for media-library
  access on behalf of the launching terminal).
- Deferred: minor (deferred): map kind of a shared Rust folder without CACHEDIR.TAG
- Deferred: minor (deferred): two process runners
- Deferred: minor (deferred): --kind filters after every rule ran
- Deferred: minor (deferred): Data-volume path key duplicated
- Deferred: minor (deferred): overlapping targets
- Deferred: minor (deferred): Gradle build folders with force-added tracked files (the cleanup step's source check covers it)
- Deferred: minor (deferred): the uv busy check counts any uv process
- Deferred: minor (deferred): tool-resource targets skip the personal-folder guard

## Rulings
- Ruling: start on Cursor CLI, not GLM — GLM's limit was exhausted for the run; cost if wrong: Cursor rounds cost more
- Ruling: the core slice's invariant "scan output byte-for-byte the same" is wrong — keeping small build folders adds nodes; the
  standing invariant is the same JSON schema and totals, with extra kept nodes; cost if wrong: a scan JSON consumer sees more nodes
- Ruling: fix two public code comments that cited a private planning document, at integration — cost if wrong: one
  comment-only commit outside the slices' files
- Ruling: accept the core round's edit to an architecture fixture — it only adds the allowed Catalog edges, and the planted
  edge stays the self-test's only violation; cost if wrong: none found
- Ruling: drop the agents round's wall-clock workaround and correct the locked stale-object test instead — the test, not the
  reader, was wrong; cost if wrong: none for production
- Ruling: the app builds fresh live rules per proposal — live readers keep their first reading; cost if wrong: one extra reader
  construction per proposal
- Ruling: a folder run lists only path candidates inside that folder — cost if wrong: Docker needs a whole-volume run
- Ruling: the git-tracked source check stays in the cleanup step, before each deletion, as the design places it — cost if
  wrong: a committed dependency folder could show as selected by default in this read-only list until cleanup blocks it
- Ruling: unused simulator runtimes need no devices and 30 days without use — deleting a runtime devices still use makes them
  unavailable; cost if wrong: fewer runtimes offered
- Ruling: leftover simulator deletion folders stay a separate candidate — measured and blocked on their own; cost if wrong: one
  more row

## Run
- 5h 11m wall clock to the review, 12 executor rounds (0 FIX): candidates-agents 2, candidates-apps 2, candidates-core 2,
  candidates-runtimes 2, candidates-screen 2, candidates-tools 2. The review's fix round ran in the coordinator, test first.

## Now
- Live: nothing; read-only, nothing runs in the background.
- Waiting on you: review and merge the pull request.
- Next: the cleanup step (staging, safety facts, the Clean button), in its own run.
