<p align="center"><img src="assets/logo.png" width="112" alt="UltraConvert icon"></p>
<h1 align="center">UltraConvert</h1>
<p align="center">Convert files locally. One selection. A clear destination.</p>
<p align="center"><a href="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml"><img src="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT licence"></a> <a href="https://github.com/samuel-zhang01/UltraConvert/releases/latest"><img src="https://img.shields.io/github/v/release/samuel-zhang01/UltraConvert" alt="Latest release"></a></p>

UltraConvert is a native macOS app with two Finder Quick Actions. Convert one file or a mixed batch of images, documents, ebooks, video, audio, geospatial data and configuration files. Files are recognised from their contents where possible, and compatible output formats appear in the app.

Conversion runs on your Mac. Originals stay in place. No account, upload service, telemetry or background daemon. **Both Finder actions support bulk conversion.**

[Install](#install) · [Enable Finder actions](#enable-the-finder-actions) · [First conversion](#your-first-conversion) · [Destinations](#choose-where-results-go) · [Useful controls](#useful-controls) · [Troubleshooting](#troubleshooting) · [Formats](#formats) · [Update / remove](#update-or-remove)

## Install

### 1. Check your Mac and prerequisites

- Open **Apple menu → About This Mac**. A **Chip** named Apple M1/M2/M3/etc. means Apple Silicon: use the release ZIP. An **Intel processor** means use the source installation below.
- Install [Homebrew from its official site](https://brew.sh), following its instructions, including the printed **Next steps** for your shell. Open a new Terminal window and run `brew --version` to confirm it is available.
- The native app targets macOS 13+. Interactive checks run on Apple Silicon/macOS 27 and engine/build CI runs on macOS 26. Intel and earlier macOS versions are unverified; Homebrew and engine support may require a newer system.

### 2. Install on Apple Silicon

1. Download **UltraConvert-…-macos-arm64.zip** from [the latest release](https://github.com/samuel-zhang01/UltraConvert/releases/latest). Do not choose GitHub's automatic “Source code” download for this route.
2. Double-click the ZIP in Finder to extract it. It contains a folder named **UltraConvert**, with `install.py` inside.
3. Open **Terminal** (Applications → Utilities). Type `cd ` with a space, drag the extracted **UltraConvert folder** from Finder into Terminal, then press Return. This handles folders with spaces or a suffix such as “UltraConvert 2”.
4. Run:

   ```sh
   python3 install.py
   ```

5. Wait until you see **Installed app** and **Next steps**. The first installation downloads substantial dependencies and can take several minutes. Homebrew may request your Mac login password; Terminal does not show characters while you type it.
6. [Enable the two Finder actions](#enable-the-finder-actions).

The installer uses the ZIP's prebuilt app, installs shared open source engines with Homebrew, and creates a local Python runtime. Keep the extracted folder if you want easy access to the uninstaller. Dragging the `.app` alone into Applications does not set up the runtime.

The binary is ad-hoc signed and **not Apple notarized**. If Gatekeeper blocks it, use a source build below. Do not disable Gatekeeper.

### Alternative: build from source

This route also applies to Intel Macs, subject to Homebrew engine availability. Install Homebrew first. Install Apple's Command Line Tools if they are missing:

```sh
xcode-select --install
```

Complete Apple's installer, then run these commands in Terminal:

```sh
git clone https://github.com/samuel-zhang01/UltraConvert.git
cd UltraConvert
python3 install.py --build-from-source
```

If you already extracted a release ZIP, navigate into that folder as described above and run `python3 install.py --build-from-source` instead. The installer accepts macOS's Python 3.9 bootstrap and uses Homebrew Python 3.14 for the conversion runtime.

### What gets installed

| Component | Location |
| --- | --- |
| Native app | `~/Applications/UltraConvert.app` |
| Two Finder workflows | `~/Library/Services/` |
| Python runtime, engine source and update backups | `~/Library/Application Support/UltraConvert/` |
| Initial default destination | `~/Downloads/UltraConvert/` |

`~` means your home folder. Homebrew conversion engines are shared installations; they are downloaded separately rather than bundled in the app.

## Enable the Finder actions

1. Open **System Settings → General → Login Items & Extensions**.
2. Scroll to **Extensions**. Find **Finder** and click its **ⓘ** information button.
3. Turn on **Convert Here with UltraConvert** and **Convert to Destination with UltraConvert**.
4. Click **Done**. Select a supported file in Finder, right-click and open **Quick Actions**.

On older macOS releases, look in **Extensions → Finder**. You can reach Login Items & Extensions from **UltraConvert → Help → Finder Action Settings**; then open the Finder list. [Apple's Quick Action guide](https://support.apple.com/en-gb/guide/automator/aut73234890a/2.10/mac/15.0) explains the system feature.

Both workflows carry UltraConvert's logo as a custom Quick Action image and Finder document icon. The logos have been verified beside both enabled actions in macOS 27's Finder Settings list. Other permission dialogs decide their own layout and may identify the Automator runner rather than the app. UltraConvert's app bundle also includes its branded icon for surfaces that show app identities.

For ordinary use, select files or folders through the native pickers and respond to any macOS access prompt for the location you chose. **Full Disk Access and Accessibility are not setup requirements.** If a folder-access prompt was denied, check **System Settings → Privacy & Security → Files & Folders** for the named requester. Do not enable unrelated permissions to make an icon appear.

## Your first conversion

Try a few photos first:

1. In Finder, select a PNG, JPEG, HEIC or another supported image. Hold **⌘** while clicking to select several files; **⇧-click** selects a range.
2. Right-click → **Quick Actions → Convert Here with UltraConvert**.
3. UltraConvert opens and recognises the files. In the **Images** row, choose an output such as **WEBP**.
4. Leave **Beside source files** selected and click **Convert**.
5. When progress finishes, click **Show Results**. A fresh **Converted …** folder contains the outputs and `conversion-report.json`. Your selected source files remain in their original folder.

For a mixed selection, one format selector appears for each detected category. For example, photos → WEBP, audio → OPUS, documents → DOCX and GIS → GPKG can share one batch. Video can also be converted to audio, such as MP4 → MP3 or OPUS. Unsupported files are identified; valid files can still be converted.

You can also open **UltraConvert** from Spotlight or `~/Applications`, drag files into the queue or click **Add Files…**, and use the same controls. Adding files appends to the queue and ignores repeats. Select queue rows and click **Remove Selected** (or press Delete); **Clear** empties the queue. These actions do not delete your original files. **Help → Quick Start** works offline. The full guide opens this README in your browser.

Batches accept up to **1,000 files**. Content probing recognises many misleading extensions; ambiguous plain text still needs an extension hint. Select a Shapefile's `.shp` file with its matching `.dbf`, `.shx` and optional `.prj` nearby. Selecting those sidecars together produces one dataset conversion.

Finder's menu contains the two actions. Choose the destination format in the native app window after the action opens.

## Choose where results go

| Choice | What happens |
| --- | --- |
| **Convert Here with UltraConvert** / **Beside source files** | Creates a new batch folder beside each source folder. Files selected from different folders get results beside their respective sources. |
| **Convert to Destination with UltraConvert** / **Saved destination** | Starts with your saved default folder, initially `~/Downloads/UltraConvert`. All results go into one fresh batch folder there. |
| **Choose destination…** or **Choose…** | Opens a folder picker. Select or create a folder, click **Open**, then click **Convert**. Cancelling the picker starts no conversion. |

To change the default: click **Choose…**, select a folder, then click **Set as Default**. The path displayed below the controls confirms where outputs will go. **File → Open Default Destination** opens the saved folder in Finder.

Every run creates a fresh batch folder. Existing outputs and originals are never overwritten. UltraConvert remembers your output formats and options for the next run; the Finder action sets the initial destination mode for that window.

## Useful controls

- **Skip files already in target format:** matching files stay at their original location and are recorded as skipped. They are not copied to the output folder.
- **Batch options:** expand this row to show skip-matching, concurrency and automatic result opening.
- **1–4 files at a time:** converts that many files at once. Two is the default. Use one for large media or GIS inputs to reduce memory pressure; four can help batches of small files.
- **Open results when finished:** automatically opens the result folder after the batch completes.
- **Cancel:** stops the current batch. Completed outputs and the partial batch report are retained.
- **Report:** selects `conversion-report.json` in Finder. Open it in a text editor to see per-file outcomes, preservation notes and engine diagnostics. For multiple source folders, reports are created in each output folder.
- **File → Copy Result Summary:** copies counts for the last completed batch, without source paths.
- **Help → Check Setup…:** checks installed engine versions, Python/GDAL imports, native icon tools and workflow files locally. It does not inspect your selected files, upload a report or confirm Finder's enable switches. **Copy Setup Report** is optional.
- **Keyboard:** ⌘O adds files; ⌘Return converts here; ⇧⌘Return chooses a folder and converts. Ordinary Return activates Convert.
- **Geospatial CRS:** enter the known input coordinate system, for example `EPSG:4326`, when required. Bare WKT needs a known CRS; do not guess one.

The file queue and output-format list scroll independently. The conversion bar keeps progress, Convert, Cancel and completed-batch actions visible. Expand **Batch options** for less frequently used controls; the main area scrolls on smaller screens. File and folder pickers remember useful starting locations. On macOS 26+, the action bar uses native Liquid Glass; older systems use a native material fallback.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `brew: command not found` or installer asks for Homebrew | Complete Homebrew's printed shell setup, open a new Terminal window, and retry `brew --version`. |
| `can't open file … install.py` | Terminal is in the wrong folder. Repeat the `cd ` + drag-folder step; the folder must contain `install.py`. |
| App blocked by macOS, or prebuilt has the wrong architecture | Run `python3 install.py --build-from-source` in the release folder after installing Command Line Tools. Intel users must build from source. |
| Quick Actions missing | Check both Finder switches above. Select files, not a directory or empty space. Reopen the Finder window; if still absent, quit UltraConvert and rerun its installer. The app's **Add Files** works independently of the menu. |
| Missing runtime, engine, or GDAL import error | Run **Help → Check Setup…**. Quit the app and rerun `python3 install.py` from the current release/source folder. The installer provisions the matching Homebrew Python/GDAL environment. |
| Permission denied for output/source folder | Choose a folder you can access with the native picker. Check the named requester in macOS **Files & Folders** permissions if you denied its prompt. |
| Some files failed | Open **Report** and read each file's error. Other files can succeed. See the preservation limits below for format-specific restrictions. |
| Valid but very large/unusual file is rejected | Resource and parser limits are deliberate. Try a smaller input or use the underlying engine directly; changing jobs does not bypass an input-size limit. |
| Unknown CRS / WKT refused | Supply the correct source CRS, or keep a matching `.prj` / SRID with the source dataset. |
| Report cannot find a report | The output folder may have been moved or removed. Use **Show Results**, or locate your batch under the displayed destination. |

For an unresolved issue, [open a GitHub issue](https://github.com/samuel-zhang01/UltraConvert/issues) with your app version, macOS version, format pair and relevant error. Review/redact conversion reports before sharing: they contain local paths and diagnostics. Setup checks are availability checks; they do not prove every codec or file will convert.

## Formats

Every listed entry passed a representative encode/decode round trip. Conversions stay within compatible categories; video can also become audio. This is not a claim that every codec, malformed file, GIS schema, or document layout is supported.

| Category | Input and output formats |
| --- | --- |
| Geospatial | geojson, gpkg, shp, kml, kmz, gpx, gml, wkt |
| Images | png, jpg, jpeg, heic, webp, tiff, bmp, ico, icns, avif |
| Documents and ebooks | docx, odt, rtf, md, html, tex, epub, mobi, azw3 |
| Video | mp4, mov, webm, mkv, avi, gif, m4v, 3gp, flv, ts, mts, m2ts, wmv, ogv, mpg, mpeg, mxf, vob |
| Audio | mp3, wav, flac, aac, m4a, ogg, wma, aiff, alac, opus, ape, wv |
| Configuration | json, yaml, yml, plist, toml |

### Preservation limits

**Images:** multi-page TIFF is retained for TIFF output; a single-image target may keep only the first page. Lossy targets change pixels. ICNS uses native icon tooling. Colour profiles and metadata are not guaranteed.

**Documents:** structural conversion, not exact page-layout preservation. Local image resources must be inside the source folder; missing, remote, or escaping resources are refused. HTML/Markdown/TeX exports bundle supporting images in the result folder. TeX is parsed, never executed. DRM-protected ebooks are unsupported.

**Media:** explicit compatibility profiles transcode the primary video/audio streams. Extra tracks, subtitles, metadata, HDR, and chapter structure are not guaranteed. GIF has no audio. ALAC writes an M4A container; APE encoding uses Monkey's Audio.

**GIS:** GeoPackage layers and Shapefile sidecars are handled as datasets. WKT has attribute/CRS sidecars; bare WKT needs `--source-crs`. Unknown CRS is refused for geographic exports. Polygon-to-GPX is refused. Legacy target formats can constrain field names, attributes, and geometry types. Output feature counts are checked, not every attribute value.

**Configuration:** safe parsing and typed round-trip comparison reject duplicate keys and unrepresentable values instead of silently changing them. Binary PLIST input works. Limits apply to size, nesting and YAML aliases.

## Command line

Optional: use the installed runtime so GDAL and the pinned parsers are available. These examples assume you are in the folder containing your source files:

```sh
UC_PY="$HOME/Library/Application Support/UltraConvert/.venv/bin/python"
UC_ENGINE="$HOME/Library/Application Support/UltraConvert/src/convert.py"
"$UC_PY" "$UC_ENGINE" --here --to webp "photo.png" "another.jpg"
"$UC_PY" "$UC_ENGINE" --output "$HOME/Downloads" --to opus "clip.mp4" "tone.wav"
"$UC_PY" "$UC_ENGINE" --here --jobs 2 --skip-same --to yaml "settings.json"
"$UC_PY" "$UC_ENGINE" --inspect "photo.png"
"$UC_PY" "$HOME/Library/Application Support/UltraConvert/src/diagnostics.py"
```

Mixed-category batches use a JSON `--plan` file such as `{"image":"webp","audio":"opus","video":"mp4","document":"docx","geo":"gpkg","config":"yaml"}`. Pass each path as a separate quoted argument. Use `--` before file paths that start with `-`. Conversion exit codes: 0 success, 1 per-file failure, 2 invalid invocation, 130 cancelled. Setup-check exit codes: 0 available, 1 needs attention.

## Engines, research and checks

FFmpeg/FFprobe (`ffmpeg-full`), ImageMagick, GDAL/OGR, Pandoc, Calibre, Monkey's Audio, Python, PyYAML, tomli-w, and defusedxml. Engines are installed separately and keep their upstream licences.

The [source review](research/REVIEW.md) examines Moonvert, MenuMate, RClick, VERT, FileConverter, HandBrake, and the conversion engines. Selected upstream source snapshots retain their licences and commit hashes. UltraConvert's original code and vector artwork are MIT licensed; that does not relicense those snapshots.

See the [release audit](docs/AUDIT.md), [verification evidence](evidence/release-verification.json), [contribution guide](CONTRIBUTING.md), and [security policy](SECURITY.md). CI checks style, static security findings, dependencies, native compilation, full format round trips, edge cases, malicious input and installer rollback.

## Update or remove

**Update:** quit every UltraConvert window, download/extract the new release, navigate into its folder in Terminal and run `python3 install.py` again. Source installs can use `git pull --ff-only` followed by `python3 install.py --build-from-source`. Saved app preferences remain. Recheck Finder switches after an update.

Managed components are staged before replacement; failed component swaps roll back. Old apps are verified in ZIP backups so Finder does not register duplicate app bundles. Shared Homebrew/Python package setup is separate from the component-swap transaction.

**Remove:** quit UltraConvert. In the extracted release folder or source checkout, run:

```sh
python3 uninstall.py
```

Removal moves only owned app, workflows and runtime into Trash. Shared Homebrew engines and converted files remain. Update backups live in the runtime and move with it. Your small macOS app-preference record is retained. Keep the Trash contents if you may want to restore the installation.

## Native macOS release and Swift roadmap

The interface is Swift/AppKit; the conversion coordinator is currently Python. A full Swift engine port can retain the established native conversion tools. The current binary is ad-hoc signed, with Hardened Runtime, and is not notarized. Developer ID signing, Apple notarization/stapling, Gatekeeper checks and optional DMG packaging are implemented in the release tooling. They require the maintainer’s distribution certificate and Keychain notarization profile; availability of the code is not a claim that Apple has accepted a release. See [the macOS release guide](docs/MACOS-RELEASE.md).
