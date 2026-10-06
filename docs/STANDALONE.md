# Standalone macOS app — development preview

The native Swift/AppKit app can run its conversion engines from inside `UltraConvert.app`. It does not need to provision Homebrew or a virtual environment on first launch. The coordinator remains Python, using a private framework/packages in the app; that implementation detail does not require a Terminal-based installation.

## Install the locally built DMG

1. Open the development DMG.
2. Drag **UltraConvert.app** onto **Applications**. The app can also live in your own `~/Applications` folder.
3. Eject the disk image and open the installed app.
4. On first launch from Applications, the app installs its two owned Finder Quick Actions. Enable them in **System Settings → General → Login Items & Extensions → Finder**. Native format Services come from the app's metadata.
5. Add files, review detected types and chosen formats, select **Beside source files** or a destination, then click **Convert**.

**UltraConvert → Settings…** (⌘,) provides optional Launch at Login, automatic Finder registration, manual action repair, Services refresh and links to macOS enable switches. Launch at Login is off unless requested by the user; its state comes from macOS, including pending approval. Disabling automatic registration leaves existing actions installed. **Help → Install Finder Quick Actions…** also repairs/repoints actions after moving the app. The app refuses to overwrite unrelated actions. Owned previous actions are retained under Application Support/backups. **Help → Check Setup…** checks local engines; **Third-Party Licences** opens the offline provenance folder's guide. Settings and reports remain in your user Library; existing source-installation runtimes are retained for rollback.

This is a **local development preview**, not an Apple-notarized public download. The first engine bundle requires **Apple Silicon and macOS 27** because its installed engine binaries require that OS. Older macOS/Intel and a fresh quarantined Mac are unverified. The complete bundle is substantial because it includes Calibre and its frameworks along with the other engines. The public v1.4.0 preview uses the separate-runtime installer; this standalone DMG remains local.

## Build and verify

On the development Mac, first provision the established dependencies with `python3 install.py --build-from-source`. Then use Homebrew Python 3.14:

```sh
python3 scripts/bundle_runtime.py --output build/standalone-dev
python3 scripts/verify_bundle.py build/standalone-dev/UltraConvert.app --output build/standalone-checks
python3 scripts/collect_runtime_sources.py build/standalone-dev/UltraConvert.app --output build/corresponding-sources --download
python3 scripts/build_development_dmg.py build/standalone-dev/UltraConvert.app --output dist/standalone-dev
```

Choose a new output directory for each app/DMG build. The bundler copies only the required Python packages, includes all conversion frontends, closes Mach-O library dependencies, rewrites library references, removes build-machine rpaths, checks symlinks, infers the actual minimum OS, signs nested code from the inside out and verifies the complete app. ImageMagick's libtool metadata lives as resources; its decoder code lives under Frameworks. No package manager runs on launch.

Bundled Python starts with `-I -S -B`: it ignores environment/user site configuration and never runs Homebrew's site customisations. The bootstrap adds only the sealed app Source and private packages. A missing or invalid manifest/tool fails with a repair message instead of using an unrelated PATH installation. Existing source builds retain the external-runtime route.

The verification runner exercises the real format/preservation/security/batch corpus with a minimal environment and a system-only PATH. Test code imports the sealed app Source, and CLI child interpreters use the same isolated private packages. This is useful portability evidence, not a clean-Mac/Gatekeeper test.

## Package size

The local Apple Silicon/macOS 27 build was reduced from **2,122,002,774 to 2,028,016,223 bytes** (about **94 MB / 4.4%**) by removing local/debug symbols from non-Calibre Mach-O files and Python C development headers/pkg-config metadata. Exported symbols, all codecs, Calibre plugins and geographic precision data are retained. The complete conversion/preservation/security/batch corpus passed against the reduced app. `ThirdParty/inventory.json` records individual reductions.

The largest components remain PROJ geographic correction grids (about 775 MiB), Calibre (637 MiB), stripped Pandoc (218 MiB) and dependent frameworks. Separating optional regional precision data or ebook engines could reduce downloads substantially, but needs explicit pack management and correctness/accuracy checks. The present builder retains offline precision grids and the complete Calibre runtime rather than silently reducing capabilities. App size and compressed DMG download size are different measurements.

## Public-release gates

The generated `Contents/Resources/ThirdParty/inventory.json` records engine/library versions, installed Homebrew recipe commits and the minimum OS. Available upstream licence texts and pinned build recipes are retained. It deliberately states `public_distribution_ready: false`; an inventory alone is not complete licence compliance.

The source collector retains the pinned recipes and downloads archive/resource URLs with their recorded SHA-256 checksums. `SOURCE-INVENTORY.json` lists verified archives and missing/unresolved items; it does not label partial collection as complete corresponding source. Archives are collected separately rather than increasing the app's size.

Before publishing a standalone binary:

- Complete and verify corresponding-source archives, build resources/patches and notices for bundled engines, Python packages and transitive dependencies. FFmpeg's installed build enables GPL components; the app's MIT licence does not replace upstream terms. Calibre also includes third-party components requiring their own inventory. [FFmpeg's distribution guidance](https://ffmpeg.org/legal.html) and the pinned recipes are the starting evidence.
- Once the maintainer's Apple membership is active, use a **Developer ID Application** certificate/private key in Keychain and a local notarization profile. Sign every nested executable/library/framework/app appropriately before signing the outer app; verify Hardened Runtime/entitlements for interpreters and Qt helpers.
- Require Apple's **Accepted** notarization result, staple app/DMG tickets, and test Gatekeeper on a fresh download with quarantine retained and on a clean Mac, including offline ticket verification.
- Re-run the full conversion corpus against the final signed artifact. Keep architecture/OS claims limited to tested systems.

The source code and local-development artifacts can be prepared while Apple reviews the account. The builder does not bypass credential requirements or advertise a development certificate as Developer ID distribution.
