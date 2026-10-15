# UltraConvert Homebrew tap

A custom tap for the signed, notarized UltraConvert macOS app and its separately installed conversion runtime. This is maintained by UltraConvert; it is not an official Homebrew Cask/Core submission.

```sh
brew tap samuel-zhang01/ultraconvert
brew install --cask ultraconvert
```

Open UltraConvert from Applications. On the first launch it registers Finder actions; enable them in macOS Settings. [Illustrated app guide](https://github.com/samuel-zhang01/UltraConvert#install).

If the same signed app is already in `/Applications`, quit it first and use `brew install --cask --adopt ultraconvert`. Homebrew refuses conflicting app copies rather than overwriting them by default. Keep one app in Applications.

Use **UltraConvert → Check for Updates…** for app downloads, installation and relaunch. Existing manual installations keep using their working per-user runtime. To update with Homebrew, finish any conversion, save rule edits and quit the app, then run:

```sh
brew update
brew upgrade ultraconvert-runtime
brew upgrade --cask --greedy ultraconvert
```

Open UltraConvert from Applications afterward. Upgrade the runtime first: its updated cleanup helper protects Finder actions when upgrading older casks. The cask declares `auto_updates`; explicit `--greedy` includes it across Homebrew versions and auto-update preferences. Ordinary upgrade behavior varies with those settings. Preferences, saved rules and existing Finder actions are retained even when automatic Finder registration is off. Files waiting in an unsaved conversion queue are not retained by an ordinary Quit; finish them or add them again after reopening.

```sh
brew uninstall --cask ultraconvert
```

Normal uninstall removes the app while preserving Finder actions, preferences, folder rules and converted files. To also remove this app's owned Finder actions, use `brew uninstall --zap --cask ultraconvert` instead. This optional cleanup moves only verified, owned workflows for the app's exact installation path to Trash; it does not erase preferences, rules or converted files. The runtime and shared engines remain installed.

The runtime also supplies `ultraconvert-engine --inspect FILE` and `ultraconvert-engine --to FORMAT --here FILE`. All conversion runs locally. Calibre, installed by the app cask, is needed for ebook conversion.

Native app: universal Apple Silicon/Intel, macOS 13+. Homebrew engines can require a newer OS; Intel hardware and engine operation remain unverified. App code/artwork: MIT; bundled Sparkle and external engines retain their own licences.

Every release pins SHA-256 digests for the app and source archive. CI audits Ruby definitions, installs the runtime, upgrades a signed app from the preceding version in this tap's history, checks a real conversion/GDAL import, and verifies that upgrades and removal preserve saved-rule/preferences fixtures. It also checks that existing Finder actions survive upgrades with automatic registration off and that optional cleanup removes only owned actions. Recipes are updated by the trusted Mac release pipeline only after release downloads and signatures are verified.
