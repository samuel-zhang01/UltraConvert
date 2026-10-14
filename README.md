<p align="center"><img src="assets/logo.png" width="96" alt="UltraConvert icon"></p>
<h1 align="center">UltraConvert</h1>
<p align="center">Convert files locally on your Mac. Keep your originals.</p>
<p align="center"><a href="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml"><img src="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT licence"></a></p>

UltraConvert is a native **Swift/AppKit macOS app** for images, audio, video, documents, ebooks, maps and structured data. Add one file or a mixed batch, choose compatible formats, and save beside the originals or in another folder. Conversion runs locally; no account, upload service or telemetry.

**Start with manual conversion.** Finder shortcuts and automatic folder rules are optional.

![UltraConvert showing the three conversion stages](docs/images/converter.png)

[Install](#install) · [First conversion](#convert-your-first-file) · [Finder](#convert-from-finder) · [Folder rules](#automate-a-folder) · [Startup](#startup-and-settings) · [Updates](#update-or-remove) · [Formats](#supported-formats) · [Help](#help-and-troubleshooting)

## Install

The **[v1.8.2 release](https://github.com/samuel-zhang01/UltraConvert/releases/tag/v1.8.2)** includes a **Developer ID signed, Apple-notarized universal app** for Apple Silicon and Intel, with in-app updates. Intel compilation is verified; Intel hardware and engine installation remain untested. Check **RELEASE-METADATA.json** and **SHA256SUMS.txt** for the package you download. The app’s notarization ticket is stapled; the signed DMG is not separately notarized.

### Homebrew installation

```sh
brew tap samuel-zhang01/ultraconvert
brew install --cask ultraconvert
```

The custom tap installs the signed app into Applications, a conversion-runtime formula and its engine dependencies. Open the app once, then enable Finder actions as described below. This tap is maintained by UltraConvert and is not an official Homebrew Core/Cask submission.

**Already installed in `/Applications`?** Quit the app, then use `brew install --cask --adopt ultraconvert`. Homebrew checks the existing app instead of overwriting a conflicting copy. Keep one app in Applications; a manual `~/Applications` copy should be moved to `/Applications` before adoption.

Use **Check for Updates…** for app updates. Use `brew upgrade ultraconvert-runtime` for the conversion runtime. Existing manual installations retain their working per-user environment. Normal `brew uninstall --cask ultraconvert` preserves preferences, folder rules and converted files; shared engines and the runtime remain installed. [Tap guide](https://github.com/samuel-zhang01/homebrew-ultraconvert).

### Manual installer

The app uses separately installed open source conversion engines. **Dragging the `.app` into Applications alone does not install those engines.** This installer sets up the app, engines and Finder actions:

1. Install [Homebrew](https://brew.sh), including its printed **Next steps**. Open a new Terminal window and confirm `brew --version` works.
2. Download **UltraConvert-1.8.2-macos-universal.zip** from the [release](https://github.com/samuel-zhang01/UltraConvert/releases/tag/v1.8.2). Use the named installer ZIP. The **DMG** contains the same installer folder: open it, copy **UltraConvert** into Downloads, then eject the disk image. The `update-macos-universal.zip` asset is for the in-app updater and requires an existing engine installation. GitHub’s automatic “Source code” downloads are for developers.
3. Double-click the ZIP. Open **Terminal**, type `cd ` with a trailing space, drag the extracted **UltraConvert folder** into Terminal, and press Return.
4. Run:

   ```sh
   python3 install.py
   ```

5. Wait for **Installed app** and **Next steps**. First setup can take several minutes and download substantial dependencies. Then open UltraConvert from Spotlight or Applications.

The native app targets macOS 13+. Hands-on checks run on Apple Silicon/macOS 27; conversion-engine support may require a newer system. The same universal ZIP contains both CPU versions; [building from source](#build-from-source) is also available. Intel hardware and engine operation are unverified.

### Build from source

Install Homebrew first. If Apple’s Command Line Tools are missing, run `xcode-select --install` and finish Apple’s installer. Then:

```sh
git clone https://github.com/samuel-zhang01/UltraConvert.git
cd UltraConvert
python3 install.py --build-from-source
```

The installer accepts macOS’s Python 3.9 bootstrap and provisions Homebrew Python for conversion. New installs use `~/Applications/UltraConvert.app`; updates reuse the managed copy in `/Applications` or `~/Applications`. Runtime and rules live in `~/Library/Application Support/UltraConvert`.

## Convert your first file

1. **Add files:** click **Add Files…** (⌘O), or drop files into the window. Recognition uses file contents where possible.
2. **Choose formats:** pick an output for each detected category, such as audio → MP3 and photos → WebP. Advice below each choice explains the format.
3. **Save to:** leave **Beside source files** selected for results directly beside the originals. For another folder, select a destination and click **Choose…**.
4. Click **Convert**. **Show Results** reveals the outputs; **Report** explains failures or skipped files.

Manual conversion keeps originals and existing outputs. Name collisions get numbered suffixes, such as `Recording (2).mp3`. Formats with companion files use one folder to keep their resources together. With **Beside source files**, different source folders retain their respective results.

**Batches:** add multiple files at once. Mixed types get separate format selectors; up to 1,000 files can share a batch. **Remove Selected** and **Clear** remove queue entries without deleting files.

**Saved destination:** choose a folder, then click **Set as Default**. Each destination batch gets a fresh folder there. The initial default is `~/Downloads/UltraConvert`.

## Convert from Finder

Enable the actions once:

1. Open **UltraConvert → Settings… → Enable Quick Actions in macOS…**.
2. In **System Settings → General → Login Items & Extensions**, find **Finder** under Extensions and open its information button.
3. Enable **Convert Here with UltraConvert** and **Convert to Destination with UltraConvert**. Older macOS versions place these under **Extensions → Finder**.

Select one or more files in Finder, right-click, and use:

| Menu item | Result |
| --- | --- |
| **Quick Actions → Convert Here with UltraConvert** | Review a batch that saves beside each original. |
| **Quick Actions → Convert to Destination with UltraConvert** | Review a batch using your saved destination. |
| **Services → Convert to MP3 / Opus / MP4 / PNG / JPEG / WebP with UltraConvert** | Review a batch with a common target preselected. |
| **Services → Convert Here with UltraConvert — Choose Format…** | Choose a category and format from all supported targets. |

**Review the formats and click Convert in the app.** Shortcuts do not silently start conversion. Both Quick Actions support multiple files.

Enable Services separately in **System Settings → Keyboard → Keyboard Shortcuts → Services**. macOS controls which appear for a selection and does not provide nested Services/Quick Actions menus; UltraConvert uses a grouped format picker. [More Finder help](docs/USAGE.md#enable-the-finder-actions).

## Automate a folder

Open **Folder Rules…** in the main window. Rules watch folders you choose and run while UltraConvert is open.

![Connected puzzle pieces in the folder rule builder](docs/images/folder-rules.png)

Start with **＋ New Rule… → Audio → MP3**, then follow the pieces:

| Piece | Choose |
| --- | --- |
| **WHEN** | An inbox folder for incoming files. |
| **IF** | Formats, categories or filenames. **ALL** requires every condition; **ANY** requires at least one. |
| **DO** | Convert/Rename actions, run top to bottom. Add from the left palette; drag grips or use Move Up/Down. |
| **SAVE** | An existing output folder outside every enabled inbox. |
| **AFTER SUCCESS** | **Keep the original** to start. Archive or Trash requires explicit acknowledgement. |

Click **Preview a File…** with a real inbox file. Preview changes no files; **View Preview Details…** shows the full plan. Block illustrations use a sample format; Preview checks your actual file.

When ready, select **Enable this rule after saving** and click **Save Rule**. Add a new file to the inbox, then inspect **Activity**. New rules start disabled; edits take effect only after saving.

Existing files are ignored when watching starts or resumes. To process them deliberately, wait for **Run Existing Files…**, then review its confirmation. Its reported count is the actual accepted count within the 1,000-file total queue limit. Repeated requests prioritise files not yet handled during the current watching session.

Rules run in priority order. A nonmatch tries the next eligible rule. A failed conversion keeps the original and does not try another rule. **Pause** stops watching. Closing the main window keeps enabled rules running; **Quit UltraConvert** stops the app.

[Full folder-rule guide](docs/USAGE.md#folder-rules): settling time, subfolders, rename tokens, archive/Trash handling, limits and recovery.

## Startup and settings

Open **UltraConvert → Settings…** (⌘,).

![UltraConvert startup and Finder settings](docs/images/settings.png)

Navigation uses short, consistent native transitions. UltraConvert respects **System Settings → Accessibility → Display → Reduce motion**; enable it for immediate transitions.

- **Launch at login:** opens UltraConvert when you sign in; off by default. Check any approval requested by macOS.
- **Start in the menu bar when folder rules are enabled:** keeps the converter out of the way at startup. The menu bar icon opens the converter/rules and pauses watching.
- **Install or Repair Quick Actions:** restores the two owned workflows using this app’s location.
- **Refresh Format Shortcuts:** registers preset Services; enable their switches separately in macOS settings.

Full Disk Access and Accessibility are not setup requirements. Use native pickers and respond to macOS access prompts for the locations you choose.

## Supported formats

| Category | Formats |
| --- | --- |
| Images | png, jpg, jpeg, heic, webp, tiff, bmp, ico, icns, avif |
| Audio | mp3, wav, flac, aac, m4a, ogg, wma, aiff, alac, opus, ape, wv |
| Video | mp4, mov, webm, mkv, avi, gif, m4v, 3gp, flv, ts, mts, m2ts, wmv, ogv, mpg, mpeg, mxf, vob |
| Documents / ebooks | docx, odt, rtf, md, html, tex, epub, mobi, azw3 |
| Geospatial | geojson, gpkg, shp, kml, kmz, gpx, gml, wkt |
| Structured data | json, yaml, yml, plist, toml |

Conversions stay within compatible categories; video can also become audio. All formats passed representative round trips. Complex layouts, every codec and metadata are not guaranteed; see [preservation limits](docs/USAGE.md#preservation-limits). DRM-protected ebooks are unsupported; TeX is parsed without execution.

Engines: FFmpeg/FFprobe, ImageMagick, GDAL/OGR, Pandoc, Calibre, Monkey’s Audio and pinned Python parsers. Public packages install them separately with their upstream licences. A full engine-bundled development app/DMG remains unpublished pending distribution review.

## Help and troubleshooting

| Problem | First check |
| --- | --- |
| `brew: command not found` | Complete Homebrew’s shell setup, then open a new Terminal window. |
| Terminal cannot find `install.py` | Repeat `cd ` + drag-folder. Choose the folder containing `install.py`. |
| Missing runtime/engine | Open **Help → Check Setup…**; rerun the current installer if needed. |
| Finder action missing | Check Finder enable switches, select files, and reopen the Finder window. |
| Rule did not run | Check saved/enabled state, Pause, Activity and whether the file predates watching. |
| Some files failed | Read each error in **Report**. Other files can still succeed. |
| Several app copies appear | Use the installer’s reported location. Updates reuse the managed app; build artifacts are not installed copies. |

Reopen **Getting Started…** for the offline guide. [Full usage and troubleshooting](docs/USAGE.md) · [Command-line usage](docs/USAGE.md#command-line).

[Report unresolved bugs](https://github.com/samuel-zhang01/UltraConvert/issues) with app/macOS versions, format pair and relevant error. Redact local paths before sharing reports.

## Update or remove

**From version 1.8 onward:** choose **UltraConvert → Check for Updates…** (also in **Settings**, ⌘,). Read the update notes, click **Install Update**, then **Install and Relaunch**. The app downloads from GitHub, checks the signed feed and archive before extraction, installs the app and reopens your queued files. Your preferences, saved rules and conversion engines are retained. Active conversions and previews finish first; save or discard any rule edits before updating.

![App update settings with daily checks and optional background downloads](docs/images/app-updates.png)

**Automatic updates:** Settings → **App updates** has three options:

- **Automatically check for updates daily** is on by default. Checks run while UltraConvert is open; no separate background monitor is installed.
- **Download updates and install when I quit** is optional and off by default. It downloads verified updates in the background and installs on a normal quit. You can still use Check for Updates to install and relaunch sooner.
- **Include preview releases** is optional and off by default for this full release. Stable releases remain available in either setting.

**Coming from 1.7 or earlier, repairing engines, or updating manually:** quit UltraConvert, extract the full installer ZIP (or copy its folder out of the DMG), and run `python3 install.py` from that folder once. Future app updates are available in the menu. Source installs can use `git pull --ff-only` followed by `python3 install.py --build-from-source`. The manual installer backs up old components and rolls back failed component swaps.

In-app updates include the native app and its conversion code. They do **not** update Homebrew, Python packages or conversion engines; use **Help → Check Setup** and rerun the full installer if an engine needs repair. Update checks contact GitHub, but send no input files or saved rules. Sparkle system profiling is disabled.

If an update fails, the existing app remains installed. Try Check for Updates again when online, or use the full installer ZIP. Running from a disk image or a read-only location can prevent updates; install using the instructions above first.

**Remove:** quit the app and run `python3 uninstall.py` from the release/source folder. Owned app, workflows and runtime move to Trash. Shared Homebrew engines and converted files remain.

## Development and verification

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [UX audits](docs/UX-AUDIT.md) · [Release/signing](docs/MACOS-RELEASE.md) · [Source research](research/REVIEW.md).

CI checks native compilation, format round trips, edge cases, malicious input, installer rollback and static/dependency security. Signing and notarization establish artifact status, not functional perfection. Original code/artwork are MIT licensed; upstream snapshots retain their licences.

## Licence and upstream source

UltraConvert’s original code and artwork use the [MIT licence](LICENSE). [Sparkle](https://github.com/sparkle-project/Sparkle) provides signed app updates; its complete licence is included at `UltraConvert.app/Contents/Resources/Sparkle-LICENSE`. Conversion engines are installed separately and retain their upstream licences. The [source review](research/REVIEW.md) links the upstream projects and explains which code is used; research snapshots retain their own licence files.
