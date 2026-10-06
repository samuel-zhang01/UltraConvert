# Native macOS distribution

The app interface, menus, file pickers, progress and Finder integration are Swift/AppKit. The coordinator and format guards are currently Python. FFmpeg, ImageMagick, GDAL, Pandoc, Calibre and Monkey's Audio perform the conversions. Changing the coordinator language does not remove those tools, and Python does not prevent signing or notarizing the native app.

## Current release status

Version 1.3.0 is Apple Silicon, ad-hoc signed with Hardened Runtime, and **not notarized**. Installation still provisions a separate Homebrew/Python runtime. It is not a self-contained drag-to-Applications app. The Developer ID/notarization branch of the release tooling has tests for its credential and acceptance gates, but requires a real distribution certificate and successful Apple submission to verify end to end.

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
  --notary-profile UltraConvert \
  --dmg
```

Use Homebrew Python 3.14 for the packaging script. The app itself still targets macOS 13. The builder:

1. Refuses a dirty public tree or a development certificate in place of Developer ID.
2. Compiles the current architecture, signs with a secure timestamp and Hardened Runtime, and verifies the signature.
3. Sends an app ZIP to Apple with `notarytool`, requires **Accepted**, staples the ticket to the app, validates it and runs Gatekeeper assessment.
4. Packages the matching committed source and app into a ZIP, preserving macOS metadata with `ditto`.
5. Optionally creates and verifies a DMG, signs it, submits it separately, staples it and checks its Gatekeeper assessment.
6. Writes source archive, checksums and `RELEASE-METADATA.json` stating signing/notarization status without credentials.

Outputs are in `dist/VERSION/`. Existing artifacts are never overwritten: choose a new directory with `--output-dir dist/VERSION-notarized` for a separate signed build. A failed or timed-out notarization stops the command; do not publish partial artifacts. Read Apple's submission log using `notarytool log` if rejected.

The optional DMG contains the complete **UltraConvert** installer-source folder. Users must still run its installer; it is not a drag-only installer. Do not advertise a self-contained bundle until the runtime is actually provisioned by the app or packaged inside it.

To build a development release, omit the signing/notarization options. Its metadata explicitly says **ad-hoc** and **not notarized**. `--dmg` alone does not provide Apple approval.

## Validate before publishing

Test a freshly downloaded signed artifact with quarantine intact on a clean Mac: first launch, setup, Finder action enablement, every representative format, cancellation, reports, update and removal. Confirm the stapled ticket works offline. A valid signature or successful notarization is not a converter correctness test, engine licence audit, or OS parser sandbox.

Local packaging can compile arm64 or x86_64. A universal app also needs matching engine/runtime availability for both architectures; the current release pipeline does not claim universal support. Intel remains unverified.

## Swift engine migration

A full Swift port should be incremental and preserve the existing fixture/security corpus:

1. Extract a typed `ConversionCore` Swift package for content recognition, plans, destinations, unique output folders and reports; keep the existing Swift UI.
2. Port bounded process execution, process-group cancellation, input fingerprints, archive/resource guards and failure isolation before format adapters.
3. Port image/media/document adapters around the same native tools. Use Foundation for JSON/PLIST, audited parsers for YAML/TOML, and GDAL C bindings or its CLI for GIS; Python GDAL would otherwise retain the Python dependency.
4. Require equivalent results across all 62 format fixtures and malicious-input checks before removing the Python engine. Preserve sidecars, multi-layer data, duplicate-key rejection and document-resource confinement.
5. Add a native first-run setup flow, or separately package/sign the engines with their licences and all dependent libraries. Only then promise a Terminal-free, drag-to-Applications installation.

Developer ID distribution is the practical first target. Mac App Store sandboxing, engine packaging and licence constraints require a separate design; notarization alone does not make the current architecture App Store-ready.
