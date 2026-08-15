# Work context

Update this file after every prompt so it acts as memory.

---

## Session log

### 2026-08-15: Fourth bug-hunt pass, real tool-path setting, no main-actor freeze, parallel folder scans

- The batch banner promised "set the tool path in Settings" but Settings had no such field. Added a real c2patool path setting: stored `c2paToolPath` on AppState (defaults key `c2paToolPath`, default `c2patool`), a Settings section with a Save button, persistence in the app scene's onChange, and `AppState.setC2PAToolPath` rebuilds the engine so `verifyFile` and `verifyFolder` use the new path immediately.
- File hashing for history records ran synchronously on the main actor: verifying a large video froze the UI while the stream was read. The record is now built inside `Task.detached` and only the small JSON write runs on the main actor.
- A history-save failure after a successful verdict was reported as "Analysis failed" and overwrote the verdict's status. The message now says the verdict is shown but could not be saved to history; engine errors keep their own message. `analyzeText`, `verifyFile`, and `verifyFolder` now return Bool so callers can tell whether a check actually ran.
- The batch report card had no scroll container and an uncapped per-file list: a large folder overflowed the window and clipped. It now scrolls and caps per-file rows at 100 with a +N more line, matching the failures cap.
- Folder scans were strictly sequential, one tool run at a time (30 s each on a hung file). `FolderVerifier` now verifies in parallel chunks of 8 via a task group, keeping the report deterministic (outcomes are collected per chunk and both lists are sorted afterwards).
- Verifying a nonexistent or non-directory path returned a silently empty report card. `FolderVerifier` now throws `FolderVerifierError.directoryNotFound` / `.directoryUnreadable` (new public enum); the app surfaces it as "Folder scan failed: ...".
- The drop zone ran c2patool on dropped folders and showed a bogus no-manifest verdict. Folders now route to the folder scan (detected via resource values, not just the URL string), and drops that were skipped because a check was running, or that contained no file URLs, say so instead of staying silent. A failed check's own error message is never clobbered by the drop notice.
- Engine suite: 49 tests pass on Linux Swift 6.0.3 (2 new: missing directory throws, file path instead of directory throws). App edits compile on macOS in CI on push.

### 2026-08-15: Third bug-hunt pass, SHA-256 quadratic fix, honest modification state, working menu shortcuts

- SHA-256 was quadratic. `Digester.update` appended every chunk to a buffer and called `removeFirst(64)` per block, shifting the remaining array each time: 8 MiB took 6.5 s, so hashing a large video (the whole point of streaming file hashes) was effectively impossible. Rewrote `update` to compress full blocks straight from the input with a carry buffer of at most 63 bytes. 8 MiB now hashes in about 0.6 s in debug, 0.06 s optimized. New test `testLargeFileHashingIsLinearNotQuadratic` hashes 8 MiB with a 5 s bound, which the old code blew past and the fixed code clears by 10x.
- `modificationState` overclaimed. With an expired certificate and a hash mismatch in the same manifest, the old code reported `modifiedSinceSigning = true` as a fact even though an unverifiable manifest cannot be attributed to its signer. It now returns nil unless the signature verifies, so the verdict stays inconclusive with no "modified after signing" evidence. New fixture `expired-hash-mismatch.json` plus a test; the mock c2patool learned the `*expired-hash*` case.
- Insufficient-input verdicts carried the wrong caveat: `Caveats.textNegative` ("No watermark detected") on a "not enough text" result. Added `Caveats.textTooShort` and used it in both insufficient-input paths; tests assert the exact string.
- The menu bar shortcuts were dead on arrival. `keyboardShortcut` on MenuBarExtra items only applies while the menu is open, so Cmd+Shift+C and Cmd+Shift+O never fired globally. Moved them to a `CommandMenu("Verify")` on the WindowGroup, removed the misleading hints from the menu bar items, and shared the actions through new `AppState.checkClipboardText()` and `AppState.pickAndVerifyFile()`. The picker now calls `NSApplication.shared.activate(ignoringOtherApps: true)` before `runModal` so the panel cannot open behind the frontmost app.
- Settings key state went stale and failures were silent. `hasAnthropicKey` was a computed read over the Keychain, which Observation cannot track, so the caption and Remove button never refreshed after save or removal, and `try?` swallowed save errors. Replaced with observable `anthropicKeyStored`, set in init and on every save/removal; save failures now set `statusMessage`.
- Multi-file drops only kept the last verdict on screen. `handleDrop` now reports "Checked N files. Each result is in History." when more than one file lands.
- Engine suite: 47 tests pass on Linux Swift 6.0.3 (3 new: hash-mismatch-without-valid-signature, too-short caveats, large-file linear bound). App edits compile on macOS in CI on push.

### 2026-08-15: Second bug-hunt pass, CI fixed and hardened

- CI was red on the last push of the previous pass: the settings rewrite re-declared `storeRawContent` (the new stored property joined a copy that already existed in the analysis-state block), and the macOS app target failed with `invalid redeclaration of 'storeRawContent'`. Removed the duplicate.
- Added a timeout to c2patool runs (30 s default, injectable through C2PAVerifier and FolderVerifier). Previously a hung tool left `isAnalyzing` true forever and silently blocked every later check. The verifier now terminates on the deadline and escalates to SIGKILL. The escalation exists because on Linux `terminate()`'s SIGTERM was not delivered when the run happened inside a Swift detached task with Task.detached pipe drains: the child kept running, `waitUntilExit()` never returned, and the app stayed stuck. A direct `kill(pid, SIGKILL)` reaped it cleanly. On timeout the drain tasks are not awaited, because a grandchild holding the pipe could keep readToEnd blocked after the direct child died.
- History corruption is now quarantined. A history.json that fails to decode is moved aside to history-corrupt-<timestamp>.json and the store starts fresh, so one bad byte cannot brick every add and delete. Test added.
- Batch report UI: when c2patool is missing, the banner alone explains it; the per-file failure list would repeat the same cause for every file. Real failure lists are capped at 20 rows with a +N more line.
- Drop zone verifies every dropped file in order instead of silently checking only the first (via a checked continuation bridging NSItemProvider).
- Menu bar clipboard and file checks open the main window before the check runs, so the user sees the spinner instead of waiting in the dark.
- History lists newest first; it previously appended oldest at the top.
- Engine suite: 44 tests pass on Linux Swift 6.0.3 (3 new: hung-tool timeout, batch timeout as per-file failure, corrupt-history quarantine). App edits compile on macOS in CI on push.

### 2026-08-15: Bug hunt pass over the macOS app

- Settings reactivity was broken by design. AppState settings were computed properties over UserDefaults on an @Observable class, and Observation only tracks stored state. Result: toggling "Anthropic detection API" never revealed the key field, and the preset caption went stale. Separately, storeRawContent (stored, observable) was never written back to UserDefaults, so the raw-content preference reset every launch. Fix: settings are now stored observable properties loaded in init, persisted by one @MainActor onChange hook in the app scene.
- Fixed a data-loss trap in Settings: the key field was prefilled with bullet characters and "Save key" would save those bullets over the real key. The field now starts empty and Save is disabled when empty.
- History list was stale: records loaded once in .task and TabView keeps tabs alive, so new checks never appeared. Now reloads when a check completes (onChange of lastTextVerdict/lastFileVerdict). "Delete all" now asks for confirmation. Verdict kinds render as human titles instead of raw enum names, search matches those titles too, the empty state distinguishes no records from no matches, and the record sheet has a Done button.
- Menu bar checks were silent: results landed in app state with no feedback. Both menu bar actions now open the main window after the check. Keyboard shortcuts added: Cmd+Return (check text), Cmd+O (choose file), Cmd+Shift+C (clipboard), Cmd+Shift+O (verify file), Cmd+Shift+S (export history).
- AppState guards against overlapping analyses and clears a stale batch report when analyzing text.
- Engine: C2PAVerifier now runs c2patool in a detached task (no main-thread freeze) and drains stdout/stderr on background threads (no pipe-buffer deadlock on large manifests). SHA-256 became an incremental digester; file records are hashed with a streaming SHA256.hashFile so verifying a large video never loads it into memory.
- Tests: 3 new (streaming hash matches one-shot, empty file hash, file record hashes content not name). 41 pass on Linux Swift 6.0.3. The macOS app edits are compiled by CI on push, since the sandbox cannot build SwiftUI.

### 2026-08-15: Full format support in the app, checksummed releases

- Closed the last format gap: the macOS app's file picker and drop zone now accept the full c2patool list (png, jpg, jpeg, svg, webp, avif, heic, heif, tif, tiff, dng, mp4, mov, m4a, mp3, wav, pdf). `CheckView` derives its allowed content types and the supported-formats caption from the engine's `MediaFormat.allCases`, so the UI cannot drift from what verification supports. jpg/jpeg, tif/tiff, and heic/heif are deduplicated by display name.
- Release framing tightened: `release.yml` now writes a machine-readable checksums.txt next to the zip, verifies it with shasum -c before publishing, and attaches it to the GitHub release alongside the zip. The SHA-256 stays in the release notes.
- `ci.yml` gained a workflow_dispatch trigger so tests and the app build can be run manually from the Actions tab.
- README updated (picker accepts the full list; checksums.txt in the release section). Engine suite still 38 tests; ran `swift test` in the sandbox before pushing.

### 2026-08-15: Pivot to OriginCheck, engine built and tested

- Owner said the web app was not the product and supplied the OriginCheck spec: a native macOS app that detects Claude content provenance through text watermark analysis and C2PA metadata verification. Old web app removed; agent.md and context.md kept and updated.
- The sandbox is Linux, so a macOS SwiftUI app cannot compile here. Installed Swift 6.0.3 on the sandbox and built the engine as a Swift package instead, which compiles and tests on Linux.
- Built OriginCheckEngine: data model, C2PAVerifier (shells out to c2patool, lenient manifest parsing), text watermark providers (local analyzer and Anthropic API provider, both honest unavailable states), verdict combiner with unknowns-reduce-confidence rules, JSON history store with hash-only defaults, dependency-free SHA-256.
- Wrote the macOS SwiftUI app package (Check, History, Settings, menu bar extra, Keychain key store). It is code-complete but must be built on a Mac.
- Fixtures: Claude-signed intact, modified after signing, unknown signer, expired certificate, plus a mock c2patool.
- Verification: 27 engine tests pass on Linux Swift 6.0.3. Found and fixed a SHA-256 byte masking bug during testing.
- Repo layout: Package.swift + Sources/ + Tests/ at root, App/ for the macOS app, Fixtures/ for test data.

### 2026-08-15: Formats expanded, batch folder verification shipped

- Added `MediaFormat` to the engine: the full list of formats c2patool verifies today, with case-insensitive extension parsing and display names. Grounded in research on c2pa-rs current support (png, jpg, jpeg, svg, webp, avif, heic, heif, tif, tiff, dng, mp4, mov, m4a, mp3, wav, pdf read-only).
- Added `FolderVerifier` to the engine: recursive folder scan, one verdict per supported file, failures collected without stopping the scan, hidden and unsupported files skipped, `toolMissing` flag when c2patool cannot launch. Returns a `BatchReport` with summary counts, sorted verdicts, and failures.
- Wrote the macOS report card UI (`BatchReportView`), a folder picker in `CheckView`, and `AppState.verifyFolder`. App target still needs a Mac build; none of the app edits compile here.
- Test suite grew from 27 to 38 tests, all passing on Linux Swift 6.0.3. New coverage: media format parsing, folder classification across format families, hidden/unsupported skipping, non-recursive scans, determinism, missing-tool behavior.
- Fixed one over-strict test that treated the hyphen in "MPEG-4 audio" as a banned dash; the voice rule bans em and en dashes, not hyphens in technical names.
- Batches are not written to history yet; a batch has no single verdict kind. Noted as a Mac-side open item.

### 2026-08-15: CI and release pipeline wired up

- Owner asked for tests on every push, a build, and a release, all framed properly with data.
- Added `.github/workflows/ci.yml`: engine tests on Linux (Swift 6.0.3 via swift-actions/setup-swift) and macOS, plus a real `swift build` of the app on a macOS 15 runner, on every push and pull request. This is the first real compile of the app target anywhere, since the sandbox is Linux.
- Added `.github/workflows/release.yml`: gates on the engine tests, builds the app in release mode, packages it via `Scripts/package-app.sh` into an ad-hoc signed OriginCheck.app, zips it, and publishes a GitHub release via the gh CLI with notes from `Scripts/release-notes.sh` (version, changelog, SHA-256, formats, install steps, privacy, known limits). Triggered by v* tags or workflow_dispatch.
- README gained a CI badge and a CI and releases section. agent.md updated with the CI/CD working notes.
- Next: watch CI turn green, then tag v0.1.0 to cut the first release. If the macOS app build surfaces Swift errors, fix them and re-push.

### 2026-08-15: CI green, first release shipped (v0.1.0)

- CI iterated on three pushes. Run 1 failed on the SwiftPM package identity gotcha: path dependencies are identified by the checkout folder name, so App/Package.swift now references the engine as package "idea" instead of "OriginCheckEngine".
- Run 2 surfaced the first real compile of the app target: Swift 6 strict concurrency errors. Task closures do not inherit MainActor isolation, so every Task touching AppState became explicitly @MainActor, and AppState itself is now @MainActor, the canonical pattern for observable app state. A Bindable local in the text editor helper needed an explicit return.
- Run 3 went green: engine tests pass on Linux and macOS, app compiles on macOS 15. The app target is now verified for the first time.
- Tagged v0.1.0 and pushed. The release pipeline gated on tests, built in release mode, packaged OriginCheck.app (ad-hoc signed) with Scripts/package-app.sh, wrote notes with Scripts/release-notes.sh, and published via gh: https://github.com/enginoor/idea/releases/tag/v0.1.0. Artifact OriginCheck-0.1.0-macOS.zip, SHA-256 f5c09a4107cbd2d22e5dd68ada674451acc3a0f57aa14dc34945fdcd2c42af36.
- Standing rules still apply: every change committed and pushed; agent.md and context.md kept current.

### 2026-08-15: Standing rule, sync after every prompt

- Owner asked that every change made in a session be committed and pushed to GitHub after every prompt. From now on, when a turn produces changes, commit them to main and push before the turn ends. Stage only the files that belong to that turn. Do not wait to be asked.

### 2026-08-15: First build (agent.md, full web app)

- Built and shipped a React web app called idea. It was removed in the next session on the owner's request and is no longer part of the repo.
