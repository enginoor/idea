# Releasing OriginCheck

This document describes the production release pipeline: how the app is
built, how the DMG is made, how Sparkle automatic updates work, and how to
cut a release. Every command here has been implemented in this repository;
run them from the repository root.

## The short version

Cut a release with one command:

```bash
bash Scripts/release.sh v1.2.0
```

That command validates the repository, checks that CI is green for the
exact commit being released, optionally pre-flights the build and DMG (when
run on a Mac), creates the version tag, pushes it, waits for the Release
workflow to finish, and verifies the published DMG.

You can also release without the script by pushing a tag:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Both paths run the same Release workflow on macOS runners. The workflow is
the single publisher: it builds the production app, packages the .app,
creates and validates the DMG, signs the DMG for Sparkle, updates the
update feed, creates the GitHub Release with the DMG attached, and verifies
the published artifact.

## What a release produces

Every release carries exactly one installable artifact:

- `OriginCheck-1.2.0.dmg`: a branded, drag-to-install disk image with the
  app and an Applications shortcut. This is the artifact users download and
  the artifact Sparkle updates from.

The GitHub Release also carries `checksums.txt` (SHA-256 of the DMG), and
the release notes contain the same checksum. The tag is `v1.2.0`, the app's
marketing version is `1.2.0`, and the app's build number (a monotonic
timestamp like `20260815120000`) is what Sparkle compares. All of them are
generated in the same workflow run from the same inputs, so they can never
disagree.

## How to build and test

Engine tests run on Linux and macOS:

```bash
swift test
```

Build the macOS app (requires a Mac):

```bash
cd App
swift package resolve   # fetches the Sparkle binary artifact
swift build -c release
```

Package the app bundle and validate it:

```bash
cd ..
bash Scripts/package-app.sh 1.2.0 20260815120000 "$PWD"
SMOKE_TEST=1 bash Scripts/validate-app.sh build/OriginCheck.app 1.2.0 20260815120000
```

Build and validate the DMG:

```bash
bash Scripts/make-dmg.sh 1.2.0 "$PWD"
SMOKE_TEST=1 bash Scripts/validate-dmg.sh build/OriginCheck-1.2.0.dmg OriginCheck.app 1.2.0 20260815120000
```

The validation scripts are the same ones the Release workflow runs. They
check the Info.plist, version and build numbers, binary architecture, the
embedded Sparkle framework, the code signature, and (with `SMOKE_TEST=1`)
that the packaged app actually launches.

## How automatic updates work

The app embeds Sparkle (`Sparkle.framework` inside the .app bundle). At
launch it starts the updater, which reads two values from Info.plist:

- `SUFeedURL`: `https://raw.githubusercontent.com/enginoor/idea/main/appcast.xml`
- `SUPublicEDKey`: the committed Sparkle public key in `Sparkle/public-key.txt`

The feed is the committed `appcast.xml`. Each release inserts an entry with
the version, build number, release date, minimum macOS version, the exact
DMG download URL, the DMG byte length, and the Sparkle EdDSA signature of
that exact DMG. The entry is inserted by `Scripts/update-appcast.py`, which
is called by the Release workflow after signing; the workflow commits the
updated feed to `main` before publishing.

When the app finds a newer build, Sparkle downloads the DMG, verifies the
signature, and asks the user before installing. `SUAutomaticallyUpdate` is
`false`, so nothing is ever installed without approval. Preferences and
history live outside the app bundle (`UserDefaults` and Application
Support), so they survive updates.

### Testing updates locally

1. Install an older release, launch it, and let it create some history.
2. Cut a newer release (or run a local update test with a higher build
   number).
3. In the app: Settings > Updates > Check for Updates..., or the app menu.

To force Sparkle to check immediately, clear its last-check marker:

```bash
defaults delete com.origincheck.app SULastCheckTime
```

Failure cases (no network, invalid feed, corrupted download, missing
artifact) are handled by Sparkle: the app keeps its current version and
reports the failure without breaking anything. Background check failures
are silent by design (`supportsGentleScheduledUpdateReminders`); only
user-initiated checks show an error.

## Sparkle signing keys

Sparkle update signatures are EdDSA (ed25519), completely separate from
Apple code signing. The public key is committed; the private key is not.

Note on key formats: Sparkle's sign_update reads the private key as base64
of the raw 32-byte Ed25519 seed (the format generate_keys -x exports), not
as PEM. The pipeline accepts either format in the SPARKLE_PRIVATE_KEY
secret: Scripts/sign-update.sh auto-detects a PEM and converts it, which
requires a full OpenSSL 3 (brew install openssl@3) on the signing machine
(macOS's bundled LibreSSL cannot parse Ed25519 PEMs).

Set up the keys once, on a Mac:

```bash
cd App && swift package resolve   # fetch Sparkle's tools
cd .. && bash Scripts/generate-sparkle-keys.sh
```

This runs Sparkle's `generate_keys` (creating the private key in your
login Keychain), writes `Sparkle/public-key.txt`, and prints the steps to:

1. Export the private key and store it as the `SPARKLE_PRIVATE_KEY`
   repository secret so the Release workflow can sign DMGs:

   ```bash
   security find-generic-password -s "Sparkle Private Key" -w > /tmp/sparkle-private-key.pem
   ```

   Paste the contents into Settings > Secrets and variables > Actions >
   New repository secret, name `SPARKLE_PRIVATE_KEY`, then delete the temp
   file.

2. Move the key to another Mac with `generate_keys -x` / `generate_keys -f`
   if you want to sign from a local release.

No Mac handy? The key is plain Ed25519. `Scripts/generate-sparkle-keys-linux.sh`
replaces step 1 with openssl 3.x: it writes the private key to
`Sparkle/private-key.pem` (gitignored) and prints the public key plus the
same remaining steps. The private key must still end up in the
`SPARKLE_PRIVATE_KEY` secret, and that step needs admin access to the
repository (a GitHub App token cannot set it).

The release pipeline refuses to run while `Sparkle/public-key.txt` is the
placeholder. Never commit the private key. The `.gitignore` blocks
`Sparkle/*.pem` and export files.

## Apple signing and notarization

The app is ad-hoc signed today, which is why first launch asks the user to
open the app manually. Developer ID signing and notarization are not wired
up because no Apple Developer certificate is configured in this repository.
When one becomes available:

- `Scripts/package-app.sh` should switch `codesign --sign -` to
  `codesign --sign "Developer ID Application: ..." --options runtime`, and
  the pipeline should notarize and staple the DMG before signing it for
  Sparkle.
- Sparkle update signing stays exactly as it is. The two systems are
  independent by design.

Nothing in this repository stores Apple signing credentials. Add them as
secrets or use the Mac's Keychain when the time comes.

## The Release workflow step by step

`.github/workflows/release.yml` runs on `v*` tag pushes and on manual
`workflow_dispatch` with a version input. It will not publish a release
unless every step succeeds:

1. Engine tests on Linux (gate job).
2. Engine tests on macOS.
3. `swift build -c release` in `App/` (with Sparkle resolved).
4. `Scripts/package-app.sh` assembles `build/OriginCheck.app`: the binary,
   the embedded Sparkle framework, the icon, and the versioned Info.plist.
5. `Scripts/validate-app.sh` validates the bundle.
6. `Scripts/make-dmg.sh` builds the DMG (dmgbuild with a branded layout;
   plain hdiutil fallback).
7. `Scripts/validate-dmg.sh` mounts the DMG and verifies the app and the
   Applications shortcut.
8. `Scripts/sign-update.sh` signs the exact DMG with the Sparkle private
   key from the `SPARKLE_PRIVATE_KEY` secret.
9. `Scripts/update-appcast.py` inserts the feed entry, then
   `Scripts/validate-feed.sh` checks the feed; the workflow commits
   `appcast.xml` to `main`.
10. Release notes and `checksums.txt` are written; the checksum file is
    verified with `shasum -c`.
11. `gh release create` publishes the tag, the DMG, and `checksums.txt`.
12. The workflow downloads the published DMG and compares its SHA-256 with
    the checksum of the artifact it built.

If the tag and release already exist (for example a retried run), the
publish step exits early and nothing is duplicated.

## Release safety checks

`Scripts/release.sh` refuses to start if:

- the working tree is dirty
- you are not on `main`
- the version is not a well-formed `X.Y.Z`
- the tag already exists locally or on the remote
- the `gh` CLI is missing or unauthenticated
- CI (`ci.yml`) has no successful completed run for the exact commit
- `Sparkle/public-key.txt` is missing or still the placeholder

The Release workflow adds its own gates: engine tests must pass inside the
workflow, the app bundle must validate, the DMG must mount, the feed must
validate, and the published artifact must byte-match the built one.

## Secrets required

| Secret | Purpose |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (PEM). Required for the Release workflow to sign the DMG. |

The Sparkle public key is committed in `Sparkle/public-key.txt` on purpose.
No other secrets exist; Apple signing credentials will be added when
Developer ID signing is configured.

## Conventions

- Version: `X.Y.Z`, tag `vX.Y.Z`.
- Build number: `date -u +%Y%m%d%H%M%S`, always increasing, used as
  `CFBundleVersion` and `sparkle:version`.
- Artifact name: `OriginCheck-<version>.dmg`.
- Feed: committed `appcast.xml`, regenerated by `Scripts/update-appcast.py`.
- Build outputs go under `build/` (gitignored).
