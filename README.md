<p align="center"><img src="assets/logo.png" width="112" alt="UltraConvert icon"></p>
<h1 align="center">UltraConvert</h1>
<p align="center">Convert files locally. One selection. A clear destination.</p>
<p align="center"><a href="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml"><img src="https://github.com/samuel-zhang01/UltraConvert/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT licence"></a> <a href="https://github.com/samuel-zhang01/UltraConvert/releases/latest"><img src="https://img.shields.io/github/v/release/samuel-zhang01/UltraConvert" alt="Latest release"></a></p>

A native macOS app and two Finder Quick Actions for batches of images, documents, ebooks, video, audio, geospatial data, and configuration files. Conversion runs on your Mac through established open source engines. No account, upload service, telemetry, or background daemon.

## Install

Install [Homebrew](https://brew.sh) first. Download the **macos-arm64 ZIP** from [Releases](https://github.com/samuel-zhang01/UltraConvert/releases/latest), extract it, and run this inside the extracted `UltraConvert` folder:

```sh
python3 install.py
```

The release includes a prebuilt Apple Silicon app. The installer installs shared conversion engines using Homebrew and creates your local Python runtime. Initial setup downloads several substantial dependencies; conversion itself is local.

For installation from source (including Intel Macs):

```sh
git clone https://github.com/samuel-zhang01/UltraConvert.git
cd UltraConvert
python3 install.py --build-from-source
```

Source builds require Apple's Xcode Command Line Tools (`xcode-select --install`). Native app deployment target is macOS 13+, but release verification is on Apple Silicon/macOS 27; older systems and Intel have not been verified. Homebrew support and engine availability may set a newer practical minimum. The download is ad-hoc signed and **not Apple notarized**. Use a source build if macOS prevents opening it; do not disable Gatekeeper.

Enable **Convert Here with UltraConvert** and **Convert to Destination with UltraConvert** under **System Settings → General → Login Items & Extensions → Finder**. On older macOS versions, look in Extensions → Finder. The app installs to `~/Applications/UltraConvert.app`, its runtime to `~/Library/Application Support/UltraConvert`, and workflows to `~/Library/Services`.

## Use it

1. Select one or many files in Finder and right-click → **Quick Actions**.
2. Choose **Convert Here** or **Convert to Destination**.
3. Choose an output format for each detected category and click **Convert**.

Both actions support mixed batches of up to 1,000 files. Compatible output choices appear in the native window. Content probing recognises many misleading extensions; ambiguous plain-text formats still need an extension hint. Selecting Shapefile sidecars together produces one dataset conversion.

- **Convert Here:** a new `Converted …` folder beside each source folder, even when selected files come from different locations.
- **Default destination:** starts at `~/Downloads/UltraConvert`. Choose another folder and click **Set as Default** to remember it.
- **Choose destination:** a native folder picker. Every run gets a fresh batch folder; originals and previous results stay in place.
- **Remembered choices:** output formats, location mode, one to four jobs, optional skipping of files already in the target format, and optional opening of results.
- **Progress and recovery:** per-file results, cancel, failure isolation, **Show Results**, and a JSON report in every output folder.
- **Keyboard:** ⌘O selects files, ⌘Return converts here, and ⇧⌘Return chooses a destination and converts. Cancelling the folder picker does not start conversion.

The app confirms the format before a batch begins. Finder's menu contains the two actions; format choices live in the app, not a nested Finder format submenu.

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

Use the installed runtime so GDAL and the pinned parsers are available:

```sh
UC_PY="$HOME/Library/Application Support/UltraConvert/.venv/bin/python"
UC_ENGINE="$HOME/Library/Application Support/UltraConvert/src/convert.py"
"$UC_PY" "$UC_ENGINE" --here --to webp photo.png another.jpg
"$UC_PY" "$UC_ENGINE" --output "$HOME/Downloads" --to opus clip.mp4 tone.wav
"$UC_PY" "$UC_ENGINE" --here --jobs 2 --skip-same --to yaml settings.json
"$UC_PY" "$UC_ENGINE" --inspect examples/Colour.png
```

Mixed-category batches use a JSON `--plan` file such as `{"image":"webp","audio":"opus","video":"mp4","document":"docx","geo":"gpkg","config":"yaml"}`. Pass paths as separate quoted arguments. Exit codes: 0 success, 1 per-file failure, 2 invalid invocation, 130 cancelled. Reports include local paths and engine diagnostics; redact them before sharing.

## Engines, research and checks

FFmpeg/FFprobe (`ffmpeg-full`), ImageMagick, GDAL/OGR, Pandoc, Calibre, Monkey's Audio, Python, PyYAML, tomli-w, and defusedxml. Engines are installed separately and keep their upstream licences.

The [source review](research/REVIEW.md) examines Moonvert, MenuMate, RClick, VERT, FileConverter, HandBrake, and the conversion engines. Selected upstream source snapshots retain their licences and commit hashes. UltraConvert's original code and vector artwork are MIT licensed; that does not relicense those snapshots.

See the [release audit](docs/AUDIT.md), [verification evidence](evidence/release-verification.json), [contribution guide](CONTRIBUTING.md), and [security policy](SECURITY.md). CI checks style, static security findings, dependencies, native compilation, full format round trips, edge cases, malicious input and installer rollback.

## Update or remove

Quit UltraConvert, obtain the new release, and run its installer. Managed components are staged before replacement; failed component swaps roll back. Old apps are verified in ZIP backups so Finder does not register duplicate app bundles.

```sh
python3 uninstall.py
```

Removal moves only owned app, workflows and runtime into Trash. Shared Homebrew engines and your converted files remain. Backups live in the runtime and are moved with it.
