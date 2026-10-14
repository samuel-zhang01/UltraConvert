# Native macOS distribution

The app interface, menus, file pickers, progress and Finder integration are Swift/AppKit. The coordinator and format guards are currently Python. FFmpeg, ImageMagick, GDAL, Pandoc, Calibre and Monkey's Audio perform the conversions. Changing the coordinator language does not remove those tools, and Python does not prevent signing or notarizing the native app.

## Current release status

The v1.8.0 full release adds Sparkle in-app updates to the universal Developer ID signed, Apple-notarized app. The complete download set includes installer ZIP and signed DMG, source archive, metadata, checksums, an app-only update ZIP and a signed update feed. The app’s ticket is stapled and Gatekeeper acceptance is verified; the DMG container is signed but not separately notarized when using Xcode’s account route. Conversion engines still require the full installer on first installation. Earlier v1.6.0 and v1.7.0 previews were also notarized; v1.3.0 and v1.5.1 were not. Metadata records each artifact’s status.

Public packages retain the separate Homebrew/Python engine installer. The complete local development app and drag-to-Applications DMG remain unpublished pending corresponding-source/notices review and complete nested-code distribution verification. See [standalone development](STANDALONE.md). Apple enrollment is approved and Developer ID provisioning is available; credentials stay in the maintainer's Keychain.

## Prepare the signing credentials

1. Use an enrolled Apple Developer Program account. Create or import a **Developer ID Application** certificate with its private key into the Mac's Keychain. In Xcode, open **Settings → Accounts**, select the account/team, then **Manage Certificates → + → Developer ID Application**. Apple's [certificate guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) lists the Account Holder requirement and the alternative developer-account route. An **Apple Development** certificate is for development, and **Developer ID Installer** is for signed `.pkg` installers.
2. Check that the distribution identity is available:

   ```sh
   security find-identity -v -p codesigning
   ```

3. Create a notarization Keychain profile interactively on your own Mac:

   ```sh
   xcrun notarytool store-credentials UltraConvert
   ```

   Follow Apple's credential prompts using your Apple ID, team ID and app-specific password, or use Apple's supported App Store Connect API-key method. Keep passwords/private keys out of chat, command history, source control and public logs. The build receives only the profile name. [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) documents authentication and submission.

Credential creation and account verification are maintainer actions. The repository does not create accounts, export signing keys or upload private keys to GitHub.

## Build a signed, notarized release

Run all checks in CONTRIBUTING.md, commit the public tree, and use the exact valid identity name printed by `security` (replace the example below):

```sh
python3 scripts/build_release.py \
  --sign-identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --architecture universal \
  --notary-profile UltraConvert \
  --dmg
```

Use Homebrew Python 3.14 for the packaging script. The app itself still targets macOS 13. The builder:

1. Refuses a dirty public tree or a development certificate in place of Developer ID.
2. Compiles the requested CPU target (`native`, `arm64`, `x86_64` or `universal`), signs with a secure timestamp and Hardened Runtime, and verifies the signature. Universal builds contain both CPU slices; engines are installed separately for the user's Mac.
3. Sends an app ZIP to Apple with `notarytool`, requires **Accepted**, staples the ticket to the app, validates it and runs Gatekeeper assessment.
4. Packages the matching committed source and app into a ZIP, preserving macOS metadata with `ditto`.
5. Optionally creates and verifies a DMG, signs it, submits it separately, staples it and checks its Gatekeeper assessment.
6. Writes source archive, checksums and `RELEASE-METADATA.json` stating signing/notarization status without credentials.

Outputs are in `dist/VERSION/`. Existing artifacts are never overwritten: choose a new directory with `--output-dir dist/VERSION-notarized` for a separate signed build. A failed or timed-out notarization stops the command; do not publish partial artifacts. Read Apple's submission log using `notarytool log` if rejected.

The optional DMG contains the complete **UltraConvert** installer-source folder. Users must still run its installer; it is not a drag-only installer. Do not advertise a self-contained bundle until the runtime is actually provisioned by the app or packaged inside it.

To build a development release, omit the signing/notarization options. Its metadata explicitly says **ad-hoc** and **not notarized**. `--dmg` alone does not provide Apple approval.

## Use Xcode’s signed-in account

When a separate notarytool profile is unavailable, build an archive for Xcode Organizer:

```sh
python3 scripts/build_xcode_archive.py \
  --sign-identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --architecture universal \
  --output build/UltraConvert-release.xcarchive
```

Open the archive in Xcode. In Organizer select **Distribute App → Direct Distribution** (or **Developer ID**, depending on Xcode version), choose upload for notarization, and use the enrolled team. Complete any Apple authentication locally. Wait for **Ready to distribute**, then **Export Notarized App** into a new folder. [Apple’s Organizer guide](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html) describes this flow.

Xcode's command-line export can also use that signed-in account. Create an export-options plist containing `method: developer-id`, `destination: upload`, `signingStyle: manual`, your `teamID` and the exact existing Developer ID certificate SHA-1 as `signingCertificate`. Then run:

```sh
xcodebuild -exportArchive \
  -archivePath build/UltraConvert.xcarchive \
  -exportOptionsPlist /absolute/path/to/ExportOptions.plist
xcodebuild -exportNotarizedApp \
  -archivePath build/UltraConvert.xcarchive \
  -exportPath /absolute/path/to/new-export-folder
```

Upload success alone is not notarization acceptance. The second command refuses an archive still processing or rejected by Apple; wait for processing and export again. It produces the notarized app for the validation step below. This route uses Xcode's existing authorization without reading its private credentials or creating a separate notarytool profile. Consult the installed `xcodebuild -help` for the supported export options.

Package that exact export from a clean committed tree:

```sh
python3 scripts/build_release.py \
  --sign-identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --notarized-app /absolute/path/to/UltraConvert.app \
  --output-dir dist/release-notarized \
  --dmg --update-assets
```

The builder checks native source provenance, exact signing certificate/team, Hardened Runtime, secure timestamp, the stapled ticket and Gatekeeper acceptance. Source, icon, version or packaging-code edits require a new archive. This route does not read or export Xcode’s private account credentials. An optional `--dmg` produces a signed image containing the notarized app, but explicitly records that the image has no separate notarization ticket. Use the Keychain-profile route to submit and staple both app and DMG.

## Validate before publishing

### In-app update signing and publication

The dependency version and SHA-256 are pinned in `scripts/sparkle.py`. The app includes its Python conversion source inside its signed resources and reuses the existing external engine environment. The framework’s unused sandbox XPC services are removed before signing; its installer, progress app and framework are signed from the inside out, then notarized with the host app.

The update signing key lives in this Mac’s login Keychain under the Sparkle account `UltraConvert`. Only its public key is committed. For a fresh maintainer setup, use the pinned distribution’s `bin/generate_keys --account UltraConvert` locally, then put its **public** key into `scripts/sparkle.py`; changing the key for existing clients requires Sparkle’s documented key-rotation procedure. Never export or upload the private key to GitHub. `--update-assets` checks that the local public key matches the key embedded in the app, signs the update archive and feed, and verifies the feed signature.

1. Finish CI, sign/notarize the exact committed universal app, then build the complete release with `--dmg --update-assets`.
2. Publish the GitHub release **with every asset first**. Download the assets and verify their SHA-256 against the local artifacts and checksums.
3. Copy the exact generated `appcast.xml` into `updates/appcast.xml`, commit and push it. This makes the update visible only after its download exists. The feed is signed: do not edit it without re-signing. Keep a previous signed feed copy to recover publication errors.
4. Verify the public feed signature, asset URL, version and size, then use Check for Updates in the installed app. For preview releases, generate the new entry with channel `preview`; stable entries have no channel.

Future app-only updates must remain compatible with the external engine requirements installed by the previous full installer. If requirements change, provide clear repair/migration instructions and test that path before advertising the update. The current release leaves engine requirements unchanged.

`scripts/prepare_update_test.py` creates a **separate bundle identifier and support directory**, builds old/new signed app copies and a local signed feed, and marks their sealed provenance as test builds so they cannot pass the public release gate. It enables local HTTP only in that explicit compile configuration. Serve its `feed` directory on port 8768 and test feed tampering, archive tampering, Install and Relaunch, queued-file/format restoration and a repeat check. Its fixture is Developer ID signed, not notarized; separately verify the exact public notarized app. See [Sparkle’s setup and testing guidance](https://sparkle-project.org/documentation/).

Test a freshly downloaded signed artifact with quarantine intact on a clean Mac: first launch, setup, Finder action enablement, every representative format, cancellation, reports, update and removal. Confirm the stapled ticket works offline. A valid signature or successful notarization is not a converter correctness test, engine licence audit, or OS parser sandbox.

Local packaging can compile arm64, x86_64 or a universal native app. Architecture lists are sealed in native provenance, checked against the executable, and recorded in release metadata. Both native slices compile locally; the installer provisions conversion engines for the user's architecture. Intel hardware, Intel engine installation and older-system operation remain unverified. See [Apple's universal binary guide](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

## Swift engine migration

A full Swift port should be incremental and preserve the existing fixture/security corpus:

1. Extract a typed `ConversionCore` Swift package for content recognition, plans, destinations, unique output folders and reports; keep the existing Swift UI.
2. Port bounded process execution, process-group cancellation, input fingerprints, archive/resource guards and failure isolation before format adapters.
3. Port image/media/document adapters around the same native tools. Use Foundation for JSON/PLIST, audited parsers for YAML/TOML, and GDAL C bindings or its CLI for GIS; Python GDAL would otherwise retain the Python dependency.
4. Require equivalent results across all 62 format fixtures and malicious-input checks before removing the Python engine. Preserve sidecars, multi-layer data, duplicate-key rejection and document-resource confinement.
5. Add a native first-run setup flow, or separately package/sign the engines with their licences and all dependent libraries. Only then promise a Terminal-free, drag-to-Applications installation.

Developer ID distribution is the practical first target. Mac App Store sandboxing, engine packaging and licence constraints require a separate design; notarization alone does not make the current architecture App Store-ready.

## Automated stable releases

CI runs for main and pull requests on hosted runners. Push an exact `vMAJOR.MINOR.PATCH` tag after merging its matching VERSION change to main. The signed-release workflow reuses all CI checks, then uses the existing `ultraconvert` + `local-macos` runner. Only the repository owner can dispatch this job, and its exact tag must be reachable from main. Pull requests never run signing jobs.

The runner needs Xcode account authorization, the existing Developer ID certificate/private key, Sparkle’s matching `UltraConvert` Keychain item, and the existing local `gh` login for the separate Homebrew tap. Keys and Xcode account credentials remain local; they are not exported to GitHub secrets. Xcode distribution logs stay in the runner’s ignored build folder and are not uploaded. The Mac must be awake and its Keychain accessible. If Apple requires renewed authorization, refresh it in Xcode and rerun the tagged workflow.

The pipeline signs/notarizes the universal app, creates the complete seven-asset release, downloads and verifies all checksums, binds the source tarball to its Git tag, checks the app signature/ticket and signed feed/archive, and atomically updates `samuel-zhang01/homebrew-ultraconvert`. Tap CI audits the definitions and tests installation, conversion, setup and preservation of rule/preferences fixtures on a fresh hosted Mac. Only after tap CI passes does the pipeline publish the exact signed feed. Existing public artifacts are immutable on a retry. A newer published release prevents a downgrade.

A manual retry uses `gh workflow run release.yml --ref vMAJOR.MINOR.PATCH`. It verifies the existing public assets before resuming tap/feed publication. No release is created by an ordinary documentation commit. Recipe templates are in `homebrew/templates`, with checksum rendering in `scripts/render_homebrew.py`.
