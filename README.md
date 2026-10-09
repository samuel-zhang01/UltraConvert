<p align="center"><img src="assets/logo.png" width="112" alt="UltraConvert icon"></p>
<h1 align="center">UltraConvert</h1>
<p align="center">Convert files locally. One selection. A clear destination.</p>
<p align="center"><a href="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml"><img src="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT licence"></a> <a href="https://github.com/samuel-zhang01/UltraConvert/releases/latest"><img src="https://img.shields.io/github/v/release/samuel-zhang01/UltraConvert" alt="Latest release"></a></p>

UltraConvert is a native macOS app with folder rules, two Finder Quick Actions and seven Finder Services. Convert one file or a mixed batch of images, documents, ebooks, video, audio, geospatial data and structured data files. Files are recognised from their contents where possible, and compatible output formats appear in the app.

Conversion runs on your Mac. Manual conversion always keeps originals; folder rules keep them by default and can explicitly archive or Trash them after success. No account, upload service or telemetry. Enabled folder rules run while the app is open, including when its main window is closed. **Both Finder actions support bulk conversion.**

[Install](#install) · [Enable Finder actions](#enable-the-finder-actions) · [First conversion](#your-first-conversion) · [Destinations](#choose-where-results-go) · [Folder rules](#folder-rules-v150-preview) · [Useful controls](#useful-controls) · [Troubleshooting](#troubleshooting) · [Formats](#formats) · [Update / remove](#update-or-remove)

## Install

The latest stable release is **v1.3.0**. The **[v1.6.0 preview](https://github.com/samuel-zhang01/UltraConvert/releases/tag/v1.6.0)** includes a **Developer ID signed, Apple-notarized native app**, with a stapled ticket, a task-based Getting Started guide, format advice and clearer folder/Finder setup. Use its installer ZIP and the steps below. Public versions install conversion engines separately. **RELEASE-METADATA.json** records the verified artifact status; older v1.5.1 and stable v1.3.0 packages are not notarized.

A self-contained v1.6.0 development app also runs locally, with all engines packaged inside `UltraConvert.app`. Its drag-to-Applications DMG is currently Apple Silicon/macOS 27 only and remains unpublished while dependency-source/licence review and complete bundled-engine distribution verification are completed. See the [standalone build guide](docs/STANDALONE.md) for developer commands and measured size reductions.

### 1. Check your Mac and prerequisites

- Open **Apple menu → About This Mac**. A **Chip** named Apple M1/M2/M3/etc. means Apple Silicon: use the release ZIP. An **Intel processor** means use the source installation below.
- Install [Homebrew from its official site](https://brew.sh), following its instructions, including the printed **Next steps** for your shell. Open a new Terminal window and run `brew --version` to confirm it is available.
- The native app targets macOS 13+. Interactive checks run on Apple Silicon/macOS 27 and engine/build CI runs on macOS 26. Intel and earlier macOS versions are unverified; Homebrew and engine support may require a newer system.

### 2. Install on Apple Silicon

1. Download **UltraConvert-…-macos-arm64.zip** from [the stable release](https://github.com/samuel-zhang01/UltraConvert/releases/latest) or the [v1.6.0 preview](https://github.com/samuel-zhang01/UltraConvert/releases/tag/v1.6.0). Do not choose GitHub's automatic “Source code” download for this route.
2. Double-click the ZIP in Finder to extract it. It contains a folder named **UltraConvert**, with `install.py` inside.
3. Open **Terminal** (Applications → Utilities). Type `cd ` with a space, drag the extracted **UltraConvert folder** from Finder into Terminal, then press Return. This handles folders with spaces or a suffix such as “UltraConvert 2”.
4. Run:

   ```sh
   python3 install.py
   ```

5. Wait until you see **Installed app** and **Next steps**. The first installation downloads substantial dependencies and can take several minutes. Homebrew may request your Mac login password; Terminal does not show characters while you type it.
6. [Enable the two Finder actions](#enable-the-finder-actions).

The installer uses the ZIP's prebuilt app, installs shared open source engines with Homebrew, and creates a local Python runtime. Keep the extracted folder if you want easy access to the uninstaller. Dragging the `.app` alone into Applications does not set up the runtime.

Use the signing/notarization status shown on the release page for the downloaded package. Older previews are ad-hoc signed and not notarized; if an older build is blocked, use the source-build route below. Do not disable Gatekeeper.

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

Start in the app; Finder shortcuts are optional:

1. Open **UltraConvert** from Spotlight or `~/Applications`. The first-use **Getting Started** guide explains conversion, Finder, folder rules and startup; you can reopen it from the main window or **Help → Getting Started**.
2. Click **Add Files…** (⌘O) or drop one or more files into **1. Add files**. UltraConvert recognises their contents and shows compatible targets.
3. In **2. Choose formats**, pick an output for each category. The advice below each choice explains uses and tradeoffs; for example, MP3 is widely compatible compressed audio, while FLAC is lossless.
4. Review **3. Save to**. **Beside source files** keeps ordinary results beside each original; **Choose destination** selects an output folder.
5. Click **Convert**. **Show Results** reveals the new files; **Report** explains failures or skipped files. Originals and existing outputs are kept.

Once comfortable, select files in Finder → right-click → **Quick Actions → Convert Here with UltraConvert** for the same review flow, or **Convert to Destination with UltraConvert** for your saved output folder.

For a mixed selection, one format selector appears for each detected category. For example, photos → WEBP, audio → OPUS, documents → DOCX and GIS → GPKG can share one batch. Video can also be converted to audio, such as MP4 → MP3 or OPUS. Unsupported files are identified; valid files can still be converted.

You can also open **UltraConvert** from Spotlight or `~/Applications`, drag files into the queue or click **Add Files…**, and use the same controls. Adding files appends to the queue and ignores repeats. Select queue rows and click **Remove Selected** (or press Delete); **Clear** empties the queue. These actions do not delete your original files. **Help → Getting Started** works offline. The full guide opens this README in your browser.

Batches accept up to **1,000 files**. Content probing recognises many misleading extensions; ambiguous plain text still needs an extension hint. Select a Shapefile's `.shp` file with its matching `.dbf`, `.shx` and optional `.prj` nearby. Selecting those sidecars together produces one dataset conversion.

For a common format, right-click → **Services → Convert to … with UltraConvert**. PNG, JPEG and WebP appear for images; MP3 and Opus for audio/video; MP4 for movies. macOS filters these shortcuts by the file type known to Finder. They open the app with that format selected and **Beside source files** chosen. Review the batch, then click **Convert**. A preset that does not suit every selected file leaves Convert disabled until you explicitly choose compatible per-category formats. They reuse an idle app window; if a batch is busy, wait or cancel before trying again. The two general Quick Actions open a fresh window with their chosen destination mode.

If a format shortcut is missing, check **System Settings → Keyboard → Keyboard Shortcuts → Services** and enable the named UltraConvert shortcut. For a misleading extension or a mixed selection that Finder cannot categorise, use the general Quick Actions or Add Files; content inspection still runs in the app.

For every supported target, use **Services → Convert Here with UltraConvert — Choose Format…**. Pick Audio, Video, Images, Documents, Geospatial or Structured data, choose a format and click **Review Conversion**. The app recognises the selection and checks compatibility before you click Convert. In the app, right-click a queue row → **Review Selected Files Here as → category → format**; targets are enabled only when every selected file supports them. This prepares the selected files for review; click Convert to start.

macOS does not expose nested submenus through Quick Actions or Services. [Apple documents that Services have no submenus](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html). A custom nested Finder menu would require a separately enabled Finder Sync extension scoped to selected folders; this preview uses supported Services and the grouped picker.

## Choose where results go

| Choice | What happens |
| --- | --- |
| **Convert Here with UltraConvert** / **Beside source files** | Places ordinary converted files directly beside their originals, without a batch folder. Files from different folders stay beside their respective sources. |
| **Convert to Destination with UltraConvert** / **Saved destination** | Starts with your saved default folder, initially `~/Downloads/UltraConvert`. All results go into one fresh batch folder there. |
| **Choose destination…** or **Choose…** | Opens a folder picker. Select or create a folder, click **Open**, then click **Convert**. Cancelling the picker starts no conversion. |

To change the default: click **Choose…**, select a folder, then click **Set as Default**. The path displayed below the controls confirms where outputs will go. **File → Open Default Destination** opens the saved folder in Finder.

For **Convert Here**, an existing output name gets a numbered suffix, such as `Recording (2).mp3`. Formats requiring multiple companion files or linked media use one adjacent folder, such as `Note-html`, to preserve their references. Destination conversions create a fresh batch folder. Existing outputs and originals are never overwritten. UltraConvert remembers your output formats and options for the next run; the Finder action sets the initial destination mode for that window.

## Startup and Finder settings (v1.5.0 preview)

Open **UltraConvert → Settings…** or press **⌘,**.

- **Launch at login:** off by default. Turning it on asks macOS to open the app at your next login. The status reflects macOS's current state, including any approval needed in **Login Items**. Turning it off unregisters the login item. Finder conversion works with this option off.
- **Start in the menu bar when folder rules are enabled:** off by default. Hides the converter at startup if enabled rules are configured. Files opened from Finder still show the converter. The menu bar icon opens the converter/rules and pauses or resumes watching.
- **Keep Finder Quick Actions installed:** on by default. Opening an installed app from Applications checks/repairs its two owned Quick Actions. Turning it off leaves existing actions available and stops automatic registration.
- **Install or Repair Quick Actions:** restores the two owned workflows and points them at this app's actual location. It preserves earlier owned workflows in backups and refuses unrelated actions. Wait for any conversion to finish first.
- **Refresh Format Shortcuts:** registers this app and refreshes its six preset shortcuts and the all-format Choose Format service.
- **Enable Quick Actions in macOS… / Enable Format Shortcuts in macOS…:** open the relevant macOS settings pane. For Services, open **Keyboard Shortcuts → Services** and enable the named shortcuts. Registration does not change macOS's enable switches.

The same registration/repair controls work in installer and standalone builds. The source/installer build still needs its separately provisioned runtime; moving the app does not move that runtime.

## Folder rules (v1.5.0 preview)

1. Open **Folder Rules…** in the converter, or **UltraConvert → Folder Rules…**.
2. Choose a template from **＋ New Rule…**: **Audio → MP3**, **Images → WebP**, **Data → YAML**, or a blank rule. New rules start as disabled drafts.
3. In the **WHEN** block, choose an inbox folder. Turn on **Include subfolders** only when needed. The wait setting requires the file to remain unchanged for 2–120 seconds before it runs.
4. In the **IF** block, choose **ALL** or **ANY**, then add conditions for detected format/category or case-insensitive filename text. Recognition uses file content where possible, not just its extension.
5. Add and reorder **Convert** and **Rename output** blocks. Rename templates accept `{name}`, `{format}` and `{date}`; do not add the extension. For example, `{name}-{format}` produces `Recording-mp3.mp3`. Sequential conversions support single-file results; companion bundles need one conversion block.
6. In **SAVE**, choose an existing output folder outside every enabled watch folder. Results are direct files unless companion resources need one folder. Name collisions get numbered suffixes.
7. Leave **Keep the original** selected, or explicitly choose **Move to archive** / **Send to Trash** and check the acknowledgement. Archive folders must also stay outside watch folders. These actions happen only after successful publication and a source-integrity check; failure/cancellation/changed-source cases keep the original. GIS and document originals must be kept because they may have companion files. They also need a conversion block when routing to preserve those companions. Trash is recoverable through Finder. If a source name is replaced during a failed final action, the earlier original is retained in a hidden recovery folder; Activity identifies its full path. Copy that path into Finder’s Go → Go to Folder to recover it without replacing the new file.
8. Click **Preview a File…** and choose an inbox file. This only recognises it and shows a plan; it changes no files. Use **Cancel Preview** or **Escape** to stop it. Editing or switching a rule invalidates an in-progress test, so old results cannot appear as the current plan. Test previews also refuse linked/changed sources and unsafe document/GIS original actions. Use **View Preview Details…** for the full source/output/archive paths and original-file consequence, even when the summary is long. Editing invalidates completed details. Check the plan, turn on **Enable this rule after saving**, then click **Save Rule**.
9. Add a new file to the inbox. **Activity** shows outcomes and offers **Reveal Output**. At most 200 local activity entries are retained.

Rules run top to bottom: the first matching enabled rule handles each file. **Move Up/Down** changes priority. **Duplicate** creates a disabled copy. Rule edits take effect only after saving. When leaving an edited rule, choose **Save Changes**, **Keep Editing** or **Discard Changes**. Discard restores the saved rule; a failed save keeps the editor open. Saving changes to enabled rules, resuming or restarting establishes a fresh baseline: existing inbox files are ignored. **Run Existing Files…** explicitly queues up to 1,000 current files using the saved rules, including their original-file policy. Pause persists across app restarts. Pausing ignores arrivals until resumed; it does not build a hidden backlog.

The menu bar icon offers **Open Converter**, **Folder Rules**, **Pause/Resume**, **Settings** and **Quit**. Closing the converter keeps enabled rules running. **Quit UltraConvert** stops watching and waits for an active automation conversion to cancel. Enable **Launch at login** in Settings if you want watching to resume when you sign in. A second UltraConvert instance can perform manual conversions but cannot run another watcher on the same rules.

Automation watches only folders you select. Hidden/temporary files, symlinks, hard links and package contents are skipped. Limits are 32 rules, 12 conditions and 8 steps per rule, 20,000 observed files, 40,000 recursive traversal entries and 1,000 queued candidates. Use a small inbox rather than your entire home or library. Files arriving while the app is closed are not automatically processed at restart. Use Run Existing Files when you intend to process them.

The watcher uses native filesystem events. It has **no polling timer or conversion engine process while idle**; one automation file converts at a time, and new automation jobs wait while a manual batch is busy. Conversion CPU/RAM depends on the engine and input; large media/GIS files can still be expensive. Rules and bounded activity are stored locally in `~/Library/Application Support/UltraConvert/Automation/`; they can contain folder paths, so review them before sharing.

## Useful controls

- **Skip files already in target format:** matching files stay at their original location and are recorded as skipped. They are not copied to the output folder.
- **Batch options:** expand this row to show skip-matching, concurrency and automatic result opening.
- **1–4 files at a time:** converts that many files at once. Two is the default. Use one for large media or GIS inputs to reduce memory pressure; four can help batches of small files.
- **Open results when finished:** reveals converted files for Convert Here, or opens the destination batch folder, after completion.
- **File-row right-click:** choose a target through **Review Selected Files Here as → category → format**, reveal the original, reveal its converted result, copy file names or error details, or remove the selected rows from the queue. Removing rows keeps the files on disk.
- **Retry Failed:** loads only failed files, recognises them again and lets you review formats/destination before another conversion.
- **Cancel:** stops the current batch. Completed outputs and the partial batch report are retained.
- **Report:** selects the conversion report in Finder. Open it in a text editor to see per-file outcomes, preservation notes and engine diagnostics. Convert Here keeps reports under `~/Library/Application Support/UltraConvert/Reports/` to avoid cluttering your source folders. Destination batches keep `conversion-report.json` in their batch folder.
- **File → Copy Result Summary:** copies counts for the last completed batch, without source paths.
- **Help → Check Setup…:** checks installed engine versions, Python/GDAL imports, native icon tools and workflow files locally. It does not inspect your selected files, upload a report or confirm Finder's enable switches. **Copy Setup Report** is optional.
- **Keyboard:** ⌘O adds files; ⌘Return converts here; ⇧⌘Return chooses a folder and converts. Ordinary Return activates Convert. ⌘Z / ⇧⌘Z undo/redo text edits; ⌘X cuts selected text; ⌘W closes the current window with its normal unsaved-change guard. Escape cancels the format chooser or an active rule test.
- **Geospatial CRS:** enter the known input coordinate system, for example `EPSG:4326`, when required. Bare WKT needs a known CRS; do not guess one.

File rows preview the source → target format. Unsupported and failed files have concise labels, with full diagnostics in their tooltip, Copy Error Details and Report. A skipped-only batch keeps Report available and hides Show Results.

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
| Folder rule did not run | Check enabled/saved state, Pause status and Activity. Only new/changed arrivals run by default; use Run Existing Files for older files. Input/output/archive folders must remain available. |
| Original action failed after conversion | The output is kept and the original is restored when possible. Activity gives a recovery path if its earlier name is occupied; hover/copy the full details and use Finder’s Go to Folder. |
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
| Structured data | json, yaml, yml, plist, toml |

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

See the [UX crawl and scoring rubric](docs/UX-AUDIT.md), [release audit](docs/AUDIT.md), [verification evidence](evidence/release-verification.json), [contribution guide](CONTRIBUTING.md), and [security policy](SECURITY.md). CI checks style, static security findings, dependencies, native compilation, full format round trips, edge cases, malicious input and installer rollback.

## Update or remove

**Update:** quit every UltraConvert window, download/extract the new release, navigate into its folder in Terminal and run `python3 install.py` again. Source installs can use `git pull --ff-only` followed by `python3 install.py --build-from-source`. Saved app preferences remain. Recheck Finder switches after an update.

Managed components are staged before replacement; failed component swaps roll back. Old apps are verified in ZIP backups so Finder does not register duplicate app bundles. Shared Homebrew/Python package setup is separate from the component-swap transaction.

**Remove:** quit UltraConvert. In the extracted release folder or source checkout, run:

```sh
python3 uninstall.py
```

Removal moves only owned app, workflows and runtime into Trash. Shared Homebrew engines and converted files remain. Update backups live in the runtime and move with it. Your small macOS app-preference record is retained. Keep the Trash contents if you may want to restore the installation.

## Native macOS release and Swift roadmap

The interface is Swift/AppKit; the conversion coordinator is currently Python. A full Swift engine port can retain the established native conversion tools. Developer ID signing, Apple notarization/stapling, Gatekeeper checks and optional DMG packaging are implemented in the release tooling. The maintainer can use a notarization Keychain profile or Xcode Organizer's signed-in account and verified export. Each release records its actual signing and app/DMG notarization status in **RELEASE-METADATA.json**; successful signing alone does not establish Apple acceptance. See [the macOS release guide](docs/MACOS-RELEASE.md).
