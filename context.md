# Work context

Update this file after every prompt so it acts as memory.

---

## Session log

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
