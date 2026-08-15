# Work context

Update this file after every prompt so it acts as memory.

---

## Session log

### 2026-08-15: Pivot to OriginCheck, engine built and tested

- Owner said the web app was not the product and supplied the OriginCheck spec: a native macOS app that detects Claude content provenance through text watermark analysis and C2PA metadata verification. Old web app removed; agent.md and context.md kept and updated.
- The sandbox is Linux, so a macOS SwiftUI app cannot compile here. Installed Swift 6.0.3 on the sandbox and built the engine as a Swift package instead, which compiles and tests on Linux.
- Built OriginCheckEngine: data model, C2PAVerifier (shells out to c2patool, lenient manifest parsing), text watermark providers (local analyzer and Anthropic API provider, both honest unavailable states), verdict combiner with unknowns-reduce-confidence rules, JSON history store with hash-only defaults, dependency-free SHA-256.
- Wrote the macOS SwiftUI app package (Check, History, Settings, menu bar extra, Keychain key store). It is code-complete but must be built on a Mac.
- Fixtures: Claude-signed intact, modified after signing, unknown signer, expired certificate, plus a mock c2patool.
- Verification: 27 engine tests pass on Linux Swift 6.0.3. Found and fixed a SHA-256 byte masking bug during testing.
- Repo layout: Package.swift + Sources/ + Tests/ at root, App/ for the macOS app, Fixtures/ for test data.

### 2026-08-15: Standing rule, sync after every prompt

- Owner asked that every change made in a session be committed and pushed to GitHub after every prompt. From now on, when a turn produces changes, commit them to main and push before the turn ends. Stage only the files that belong to that turn. Do not wait to be asked.

### 2026-08-15: First build (agent.md, full web app)

- Built and shipped a React web app called idea. It was removed in the next session on the owner's request and is no longer part of the repo.
