# Conversion and Finder integration source review

Observed 2026-10-06. The result is **UltraConvert**, a native macOS app launched by two Finder Quick Actions and backed by established local conversion engines. All 62 requested entries passed representative write/read checks. Format support has real preservation limits, described in [the guide](../README.md).

## Moonvert source findings

Reviewed [kavostudio/moonvert](https://github.com/kavostudio/moonvert) at `90c3740ef84fcdbb12df128844a42fa6bdd78ad6`. Selected source files, licences, commit and SHA-256 hashes are retained in [source-snapshot.json](source-snapshot.json) and `moonvert-source`. This is a source audit, not a comprehensive audit of the downloaded binary.

Moonvert's Electron front end dispatches work through process/worker bridges. Its batch handler bounds concurrency relative to CPU count, streams progress and provides cancellation. This is a useful pattern; UltraConvert uses two jobs by default because each media/document/GIS worker can consume significant resources. [Batch handler](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/main/ipc/conversion-handler.ts).

Recognition in the renderer relies on extensions. The routing table disables WKT and ICO input, has no ICNS input entry, and offers HEIC input without HEIC output. ALAC/APE/WV are primarily input routes, rather than general output choices. These routes do not fulfil the requested bidirectional coverage. UltraConvert probes content and offers compatible targets by category. [File recognition](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/renderer/routes/main/file-utils.ts), [format routes](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/shared/config/converter-config.ts).

The Pandoc bridge maps MOBI/AZW3 to EPUB reader/writer identifiers without an actual Kindle conversion stage in that bridge. EPUB bytes under a Kindle extension are insufficient, and genuine Kindle input needs a proper reader. UltraConvert uses Calibre around a Pandoc EPUB intermediary and checks the container signature. [Pandoc bridge](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/main/converters/bridges/process-based/pandoc-bridge.ts), [Calibre CLI](https://manual.calibre-ebook.com/generated/en/ebook-convert.html).

The media bridge declares an APE encoder profile, but the installed FFmpeg encoder inventory has no APE encoder. UltraConvert uses Monkey's Audio for that step. ALAC is written in an M4A container. Build choices also matter: the existing minimal FFmpeg here lacked Theora/Vorbis encoders, while `ffmpeg-full` supplied them. [Moonvert media arguments](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/main/converters/bridges/process-based/ffmpeg/ffmpeg-args.ts), [FFmpeg full package](https://formulae.brew.sh/formula/ffmpeg-full), [Monkey's Audio package](https://formulae.brew.sh/formula/mac).

The GIS script reads a default layer rather than enumerating layers. It extracts KMZ to KML, then still passes the original input path to the reader; success depends on the reader's native KMZ support. Its KMZ writer chooses KML without an explicit ZIP container step. WKT export writes geometry text without attribute/CRS sidecars. These are source-level gaps, not proof that every operation in the released app fails. UltraConvert uses LIBKML for real KMZ, processes nonempty layers, bundles sidecars and checks feature counts. [GIS source](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/python/convert_geo.py), [LIBKML driver](https://gdal.org/en/stable/drivers/vector/libkml.html).

The structured worker uses UTF-8 text and a JavaScript PLIST parser. Binary PLIST and cross-format type preservation need additional handling. UltraConvert uses Python's XML/binary PLIST support and typed round-trip comparison; duplicate keys or unrepresentable values fail explicitly. [Structured worker](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/main/workers/structured-worker/structured-worker.ts), [plistlib](https://docs.python.org/3/library/plistlib.html).

Moonvert has trial/licence checks in its published application. The existing installation was retained without altering these checks. Its AGPL source is useful to study; the runtime here is independently written. [Licence service](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/src/main/services/license-service.ts), [upstream licence](https://github.com/kavostudio/moonvert/blob/90c3740ef84fcdbb12df128844a42fa6bdd78ad6/LICENSE).

## Other interesting projects

| Project | Relevant design | Fit for this request |
|---|---|---|
| [MenuMate](https://github.com/Hibrielle/menumate) | MIT Finder Sync source builds dynamic submenus, reads selected URLs and sends bounded/chunked requests to its host. | A useful model for a future direct **Convert → format** submenu. Adds an extension/host communication layer; not a turnkey converter for this complete format list. |
| [RClick](https://github.com/wflixu/RClick) | GPL-3.0 Finder Sync renders cached menus and forwards selection/action events, with heartbeats and acknowledgements. | Broader menu framework demonstrating reliability work beyond adding a menu item. Modern macOS/toolchain requirements narrow portability. |
| [VERT](https://github.com/VERT-sh/VERT) | AGPL-3.0 browser dispatcher with document/image/media adapters and an optional video daemon path. | Interesting browser/WASM UX. Video processing location depends on the selected backend; it does not provide this Finder/GIS integration. |
| [FileConverter](https://github.com/Tichau/FileConverter) | GPL-3.0 Windows Explorer integration, job factory and explicit FFmpeg format converters. | Strong batch-preset inspiration; Windows shell/.NET integration cannot serve as a macOS Finder action. |
| [HandBrake](https://github.com/HandBrake/HandBrake) | Mature video queue and transcoding presets. | Useful for video-specific workflows, not this document/GIS/image/configuration scope. |
| [contextmenu-actions](https://github.com/gingerbeardman/contextmenu-actions) | Small native contextual workflow examples. | Close to a personal Quick Action; still requires engine dispatch, recognition, destination choices and batch reporting. |

Selected alternative source files and licences are pinned in [alternative-source-snapshot.json](alternative-source-snapshot.json). Reviewed commits: MenuMate `5e424cd3…`, RClick `91e92109…`, VERT `91091a1b…`, FileConverter `6c157a41…`. They are retained evidence, not runtime imports.

Apple supports Automator workflows receiving selected Finder files. The supplied contextual-menu article and Automator tutorial describe this route. The supplied YouTube page could not be independently retrieved. One Quick Action launching a native picker avoids dozens of separate target workflows and supports mixed categories in one run. [Apple guide](https://support.apple.com/guide/automator/create-workflows-aut7cac58839/2.10/mac/27), [context-menu article](https://blog.gingerbeardman.com/2024/07/30/taking-command-of-the-context-menu-in-macos/), [Automator tutorial](https://rajeev.dev/how-to-create-context-menu-actions-on-macbooks).

The installed Finder item opens a format/destination picker. Putting every target directly in Finder's submenu would require a Finder Sync extension, modelled on MenuMate/RClick. Both actions support mixed batches and saved/default destinations. The current app needs no extension process, converter account or permanent background daemon.

## Why several engines are necessary

FFmpeg handles media streams/containers. An extension alone does not define quality, compatibility or retained tracks; explicit profiles and stream mapping are necessary. FFprobe checks the output, and engine commands/messages are retained in the batch report. [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html), [source](https://github.com/FFmpeg/FFmpeg).

ImageMagick supplies image codecs when their delegates are available. Native macOS tools provide the ICNS path. Actual encode/decode checks are more reliable than assuming all builds have identical codec support. [Format documentation](https://imagemagick.org/formats/), [source](https://github.com/ImageMagick/ImageMagick).

Pandoc converts document structure across office/text/EPUB formats; it does not preserve exact page layout or implement Kindle formats. Calibre supplies MOBI/AZW3 conversion; DRM-protected input remains unsupported. Local images are embedded or bundled, while missing resources fail. [Pandoc manual](https://pandoc.org/MANUAL.html), [Pandoc source](https://github.com/jgm/pandoc), [Calibre source](https://github.com/kovidgoyal/calibre), [Calibre FAQ](https://manual.calibre-ebook.com/faq.html).

GDAL/OGR provides vector drivers, layers and reprojection. GeoPackage holds multiple layers; Shapefile's legacy field/geometry limits and GPX's restricted geometries still matter after a successful export. UltraConvert refuses polygon→GPX and requires known CRS for geographic exports. [ogr2ogr](https://gdal.org/en/stable/programs/ogr2ogr.html), [GeoPackage](https://gdal.org/en/stable/drivers/vector/gpkg.html), [Shapefile](https://gdal.org/en/stable/drivers/vector/shapefile.html), [GPX](https://gdal.org/en/stable/drivers/vector/gpx.html), [source](https://github.com/OSGeo/gdal).

Configuration conversion needs parsers and semantic validation. Null, dates, bytes, root structures and duplicate keys are not equally representable across JSON/YAML/TOML/PLIST. Safe YAML loading and typed comparison prevent common silent coercions. [PyYAML](https://pyyaml.org/wiki/PyYAMLDocumentation), [tomllib](https://docs.python.org/3/library/tomllib.html), [plistlib](https://docs.python.org/3/library/plistlib.html).

## Verification and boundaries

The full suite generated six category fixtures, wrote all 62 entries, recognised each output and converted it back. It checked representative document text, typed configuration and GIS features. Additional checks covered unchanged originals, binary PLIST, duplicate keys, WKT CRS, multi-layer export, quoted filenames, mixed-batch failure isolation and clean staging. [Full evidence](../evidence/format-verification.json).

The edge suite checked document image bytes and relative exports, missing/remote image refusal, Shapefile sidecar selection, multi-page TIFF, misleading extensions and cancellation. [Edge evidence](../evidence/edge-verification.json). These fixtures do not cover all exotic codecs, damaged files, complex ebooks, colours, schemas or large datasets. Reports expose limits; retaining all tracks, exact layout or all GIS attributes needs further profiles and domain-specific validation.

## Licences and reuse

UltraConvert's independent source is MIT licensed. The retained excerpts keep their original notices: Moonvert/VERT AGPL-3.0; RClick/FileConverter GPL-3.0; MenuMate MIT. UltraConvert's MIT licence does not cover those research directories.

Engines are separate Homebrew/vendor installations. Upstream projects/package builds supply their licences: FFmpeg licensing depends on enabled components; Pandoc/Calibre use GPL licences; GDAL is permissively licensed; ImageMagick has its own permissive licence; the packaged Monkey's Audio uses BSD-3-Clause. UltraConvert does not bundle their binaries. Embedding or distributing engines requires checking the actual build and notices separately. This is a source inventory, not a legal opinion.
