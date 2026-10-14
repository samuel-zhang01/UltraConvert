# UltraConvert Homebrew tap

A custom tap for the signed, notarized UltraConvert macOS app and its separately installed conversion runtime. This is maintained by UltraConvert; it is not an official Homebrew Cask/Core submission.

```sh
brew tap samuel-zhang01/ultraconvert
brew install --cask ultraconvert
```

Open UltraConvert from Applications. On the first launch it registers Finder actions; enable them in macOS Settings. [Illustrated app guide](https://github.com/samuel-zhang01/UltraConvert#install).

If the same signed app is already in `/Applications`, quit it first and use `brew install --cask --adopt ultraconvert`. Homebrew refuses conflicting app copies rather than overwriting them by default. Keep one app in Applications.

Use **UltraConvert → Check for Updates…** for app downloads, installation and relaunch. Use `brew upgrade ultraconvert-runtime` to update the conversion runtime. Existing manual installations keep using their working per-user runtime. The cask declares `auto_updates`, so ordinary `brew upgrade` leaves in-app app updates to UltraConvert; `brew upgrade --cask --greedy ultraconvert` explicitly updates the cask too.

```sh
brew uninstall --cask ultraconvert
```

Normal uninstall removes the app and its owned Finder actions, while preserving preferences, folder rules and converted files. The runtime and shared engines remain installed. No `zap` command is defined.

The runtime also supplies `ultraconvert-engine --inspect FILE` and `ultraconvert-engine --to FORMAT --here FILE`. All conversion runs locally. Calibre, installed by the app cask, is needed for ebook conversion.

Native app: universal Apple Silicon/Intel, macOS 13+. Homebrew engines can require a newer OS; Intel hardware and engine operation remain unverified. App code/artwork: MIT; bundled Sparkle and external engines retain their own licences.

Every release pins SHA-256 digests for the app and source archive. CI audits Ruby definitions, installs the runtime and app, checks a real conversion/GDAL import, and verifies that uninstall preserves a saved-rule/preferences fixture. Recipes are updated by the trusted Mac release pipeline only after release downloads and signatures are verified.
