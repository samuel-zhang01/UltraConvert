#!/usr/bin/env python3
"""Local batch conversion engine. No shell interpolation; originals are read only."""

import argparse
import base64
import concurrent.futures
import datetime
import errno
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import zipfile
from pathlib import Path
from urllib.parse import unquote, urlsplit

from defusedxml import ElementTree

import guards
import structured
from runtime_tools import runtime_environment, tool

FORMATS = {
    "geo": "geojson gpkg shp kml kmz gpx gml wkt".split(),
    "image": "png jpg jpeg heic webp tiff bmp ico icns avif".split(),
    "document": "docx odt rtf md html tex epub mobi azw3".split(),
    "video": "mp4 mov webm mkv avi gif m4v 3gp flv ts mts m2ts wmv ogv mpg mpeg mxf vob".split(),
    "audio": "mp3 wav flac aac m4a ogg wma aiff alac opus ape wv".split(),
    "config": "json yaml yml plist toml".split(),
}
ALIASES = {
    "tif": "tiff",
    "heif": "heic",
    "markdown": "md",
    "htm": "html",
    "aif": "aiff",
    "azw": "azw3",
}
PANDOC = {
    "md": "markdown",
    "html": "html",
    "tex": "latex",
    "epub": "epub",
    "docx": "docx",
    "odt": "odt",
    "rtf": "rtf",
}
AUDIO = {
    "mp3": ["-c:a", "libmp3lame", "-q:a", "2"],
    "wav": ["-c:a", "pcm_s24le"],
    "flac": ["-c:a", "flac"],
    "aac": ["-c:a", "aac", "-b:a", "192k", "-f", "adts"],
    "m4a": ["-c:a", "aac", "-b:a", "192k", "-f", "ipod"],
    "ogg": ["-c:a", "libvorbis", "-q:a", "6"],
    "wma": ["-c:a", "wmav2", "-b:a", "192k", "-f", "asf"],
    "aiff": ["-c:a", "pcm_s24be"],
    "alac": ["-c:a", "alac", "-f", "ipod"],
    "opus": ["-c:a", "libopus", "-b:a", "128k"],
    "wv": ["-c:a", "wavpack"],
}
CANCEL = threading.Event()
PROCESSES = set()
LOCK = threading.Lock()
ENGINE_ENV = {
    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
    "PYTHONDONTWRITEBYTECODE": "1",
    "MAGICK_CONFIGURE_PATH": str(Path(__file__).resolve().parent),
    "MAGICK_THREAD_LIMIT": "2",
    "PROJ_NETWORK": "OFF",
    "LIBKML_EXTERNAL_STYLE": "NO",
    "LIBKML_RESOLVE_STYLE": "NO",
    "GML_SKIP_RESOLVE_ELEMS": "ALL",
    "GML_DOWNLOAD_SCHEMA": "NO",
    "GDAL_HTTP_TIMEOUT": "10",
}
ENGINE_ENV.update(runtime_environment())
for key in ("GDAL_DATA", "PROJ_DATA", "GDAL_DRIVER_PATH"):
    if key in ENGINE_ENV:
        os.environ[key] = ENGINE_ENV[key]
for key in (
    "PROJ_NETWORK",
    "LIBKML_EXTERNAL_STYLE",
    "LIBKML_RESOLVE_STYLE",
    "GML_SKIP_RESOLVE_ELEMS",
    "GML_DOWNLOAD_SCHEMA",
):
    os.environ[key] = ENGINE_ENV[key]


def run(args, cwd=None, log=None, timeout=21600):
    if CANCEL.is_set():
        raise InterruptedError("Conversion cancelled")
    args = [tool(args[0]), *map(str, args[1:])]
    env = dict(os.environ, **ENGINE_ENV)
    # File-backed streams prevent verbose/malicious engines exhausting memory or
    # deadlocking the caller's pipe readers. Only a bounded result/tail is read.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(
            args, cwd=cwd, env=env, stdout=out, stderr=err, start_new_session=True
        )
        with LOCK:
            PROCESSES.add(process)
        started = time.monotonic()
        stopping = None
        timed_out = False
        try:
            while process.poll() is None:
                now = time.monotonic()
                if CANCEL.is_set() or now - started > timeout:
                    timed_out = timed_out or now - started > timeout
                    if stopping is None:
                        stopping = now
                        try:
                            os.killpg(process.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    elif now - stopping > 2:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                if out.tell() > 32 * 1024 * 1024 or err.tell() > 8 * 1024 * 1024:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                    raise ValueError("Engine output exceeded the safety limit")
                try:
                    process.wait(timeout=0.1)
                except subprocess.TimeoutExpired:
                    pass
            process.wait()
            if os.fstat(err.fileno()).st_size > 8 * 1024 * 1024:
                raise ValueError("Engine output exceeded the safety limit")
            out.seek(0)
            raw = out.read(32 * 1024 * 1024 + 1)
            if len(raw) > 32 * 1024 * 1024:
                raise ValueError("Engine output exceeded the safety limit")
            stdout = raw.decode("utf-8", errors="replace")
            err.seek(0, os.SEEK_END)
            err.seek(max(0, err.tell() - 2000))
            stderr = err.read().decode("utf-8", errors="replace")
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            with LOCK:
                PROCESSES.discard(process)
    if log is not None:
        log.append({"command": args, "stderr": stderr, "returncode": process.returncode})
    if CANCEL.is_set():
        raise InterruptedError("Conversion cancelled")
    if timed_out:
        raise TimeoutError(f"{Path(args[0]).name} exceeded the conversion time limit")
    if process.returncode:
        detail = stderr.strip() or stdout.strip() or "conversion failed"
        raise RuntimeError(f"{Path(args[0]).name}: {detail[:2000]}")
    return stdout


def probe(path):
    return json.loads(
        run(
            [
                "ffprobe",
                "-v",
                "error",
                "-protocol_whitelist",
                "file,pipe",
                "-show_format",
                "-show_streams",
                "-of",
                "json",
                path,
            ],
            timeout=60,
        )
    )


def inspect(path):
    path = Path(path).expanduser().absolute()
    info = {
        "path": str(path),
        "name": path.name,
        "format": "",
        "category": "",
        "targets": [],
        "error": None,
    }
    try:
        if path.is_symlink():
            path = path.resolve(strict=True)
            info["path"] = str(path)
        if not path.is_file():
            raise ValueError("Select files; folders are not converted recursively")
        metadata = path.stat()
        info["fingerprint"] = [
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_size,
            metadata.st_mtime_ns,
        ]
        ext = ALIASES.get(path.suffix[1:].lower(), path.suffix[1:].lower())
        with path.open("rb") as stream:
            head = stream.read(8192)
        fmt, category, media = None, None, None
        if head.startswith(b"PK") and zipfile.is_zipfile(path):
            guards.validate_archive(path)
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                if "word/document.xml" in names:
                    fmt, category = "docx", "document"
                elif "mimetype" in names and archive.getinfo("mimetype").file_size < 256:
                    mime = archive.read("mimetype").strip()
                    if mime == b"application/epub+zip":
                        fmt, category = "epub", "document"
                    elif mime == b"application/vnd.oasis.opendocument.text":
                        fmt, category = "odt", "document"
                if fmt is None and any(n.lower().endswith(".kml") for n in names):
                    fmt, category = "kmz", "geo"
        elif head.startswith(b"bplist00"):
            fmt, category = "plist", "config"
        elif head.startswith(b"{\\rtf"):
            fmt, category = "rtf", "document"
        elif head.startswith(b"icns"):
            fmt, category = "icns", "image"
        elif head[60:68] == b"BOOKMOBI":
            fmt, category = ("azw3" if ext == "azw3" else "mobi"), "document"
        elif head.startswith(b"SQLite format 3"):
            from osgeo import gdal

            ds = gdal.OpenEx(str(path), gdal.OF_VECTOR | gdal.OF_READONLY, allowed_drivers=["GPKG"])
            if ds and ds.GetDriver().ShortName == "GPKG":
                fmt, category = "gpkg", "geo"
        if not fmt and (head.lstrip().startswith(b"<") or b"<plist" in head):
            try:
                with path.open("rb") as stream:
                    root = next(ElementTree.iterparse(stream, events=("start",)))[1].tag
                local = root.split("}")[-1].lower()
                if local in ("kml", "gpx", "plist"):
                    fmt, category = local, ("config" if local == "plist" else "geo")
                elif "opengis.net/gml" in root or ext == "gml":
                    fmt, category = "gml", "geo"
                elif local == "html":
                    fmt, category = "html", "document"
            except ElementTree.ParseError:
                pass
        if not fmt and (head.lstrip().startswith((b"{", b"[")) or ext in ("json", "geojson")):
            try:
                if metadata.st_size > guards.MAX_CONFIG_BYTES and ext == "geojson":
                    fmt, category = "geojson", "geo"
                    data = None
                else:
                    data = structured.load(path, "json")
                geotypes = {
                    "Feature",
                    "FeatureCollection",
                    "Point",
                    "LineString",
                    "Polygon",
                    "MultiPoint",
                    "MultiLineString",
                    "MultiPolygon",
                    "GeometryCollection",
                }
                geo = (
                    isinstance(data, dict)
                    and data.get("type") in geotypes
                    and any(
                        k in data for k in ("geometry", "coordinates", "features", "geometries")
                    )
                )
                if not fmt:
                    fmt, category = ("geojson", "geo") if geo else ("json", "config")
            except ValueError, UnicodeDecodeError:
                if ext in ("json", "geojson"):
                    raise
        mime = run(["file", "-b", "--mime-type", str(path)], timeout=30).strip() if not fmt else ""
        if not fmt and (mime.startswith("image/") or ext in FORMATS["image"]):
            with tempfile.TemporaryDirectory(prefix="ultraconvert-identify-") as temp:
                safe_input = Path(temp) / ("input." + (ext if ext in FORMATS["image"] else "img"))
                safe_input.symlink_to(path)
                identified = run(
                    ["magick", "identify", "-ping", "-format", "%m\n", safe_input], timeout=60
                ).splitlines()
            image_fmt = identified[0].lower()
            image_fmt = {"jpeg": "jpg", "heif": "heic", "icon": "ico"}.get(image_fmt, image_fmt)
            if image_fmt == "gif":
                fmt, category = "gif", "video"
            elif image_fmt in FORMATS["image"]:
                fmt, category = image_fmt, "image"
            else:
                raise ValueError(f"Image format {image_fmt} is outside the configured set")
        if not fmt and (ext in FORMATS["geo"]):
            fmt, category = ext, "geo"
        if not fmt and ext in FORMATS["config"]:
            structured.signature(structured.load(path, ext))
            fmt, category = ext, "config"
        if not fmt and ext in FORMATS["document"]:
            fmt, category = ext, "document"
        if not fmt:
            media = probe(path)
            streams = media.get("streams", [])
            video = any(
                s["codec_type"] == "video" and not s.get("disposition", {}).get("attached_pic")
                for s in streams
            )
            audio = any(s["codec_type"] == "audio" for s in streams)
            category = "video" if video else "audio" if audio else None
            if not category:
                raise ValueError("Could not recognise a supported file format")
            container = media.get("format", {}).get("format_name", "").split(",")[0]
            mapped = {
                "matroska": "mkv",
                "asf": "wmv" if video else "wma",
                "mpegts": "ts",
                "mpeg": "mpg",
                "wavpack": "wv",
                "mov": "mp4" if video else "m4a",
            }
            compatible = {
                "mov": ["mp4", "mov", "m4v", "3gp", "m4a", "alac"],
                "matroska": ["mkv", "webm"],
                "asf": ["wmv", "wma"],
                "mpegts": ["ts", "mts", "m2ts"],
                "mpeg": ["mpg", "mpeg", "vob"],
                "ogg": ["ogg", "ogv", "opus"],
                "wavpack": ["wv"],
            }
            fmt = (
                ext
                if ext in compatible.get(container, [container]) and ext in FORMATS[category]
                else mapped.get(container, container)
            )
            if container == "ogg" and video:
                fmt = "ogv"
            if container == "ogg" and audio and any(s.get("codec_name") == "opus" for s in streams):
                fmt = "opus"
            if category == "audio" and any(s.get("codec_name") == "alac" for s in streams):
                fmt = "alac"
            if fmt not in FORMATS[category]:
                raise ValueError(
                    f"Recognised {container}; no configured conversion profile for this format"
                )
        targets = list(FORMATS[category])
        if category == "video":
            media = media or probe(path)
            if any(s["codec_type"] == "audio" for s in media.get("streams", [])):
                targets += FORMATS["audio"]
        if category == "config":
            structured.signature(structured.load(path, fmt))
        if (
            category == "document"
            and fmt in ("md", "html", "tex", "rtf")
            and metadata.st_size > guards.MAX_TEXT_BYTES
        ):
            raise ValueError("Text document exceeds the 64 MiB safety limit")
        info.update(format=fmt, category=category, targets=targets)
    except Exception as exc:
        info["error"] = str(exc)
    return info


def image_convert(source, fmt, dest, target, stage, execute):
    notes = []
    # A safe basename prevents ImageMagick treating brackets/colons in filenames as image syntax.
    link = stage / f"_input.{fmt}"
    link.symlink_to(source)
    try:
        actual = link
        if fmt == "icns":
            actual = stage / "_icns.png"
            execute(["sips", "-s", "format", "png", str(link), "--out", str(actual)])
            notes.append(
                "ICNS input uses the native macOS image representation; original icon size variants may be collapsed."
            )
        if target == "icns":
            iconset = stage / "_icon.iconset"
            iconset.mkdir()
            for size in (16, 32, 128, 256, 512):
                for scale in (1, 2):
                    px = size * scale
                    name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                    execute(
                        [
                            "magick",
                            str(actual) + "[0]",
                            "-auto-orient",
                            "-resize",
                            f"{px}x{px}",
                            "-background",
                            "none",
                            "-gravity",
                            "center",
                            "-extent",
                            f"{px}x{px}",
                            str(iconset / name),
                        ]
                    )
            execute(["iconutil", "-c", "icns", str(iconset), "-o", str(dest)])
            shutil.rmtree(iconset)
            notes.append("ICNS generated at standard macOS icon sizes; first source image is used.")
        else:
            args = ["magick", str(actual), "-auto-orient"]
            if target in ("jpg", "jpeg", "bmp"):
                args += ["-background", "white", "-alpha", "remove", "-alpha", "off"]
                notes.append("Destination flattens transparency onto white.")
            if target == "ico":
                args += ["-resize", "256x256", "-define", "icon:auto-resize=256,128,64,48,32,16"]
            execute([*args, str(dest)])
            outputs = list(stage.glob(f"*.{target}"))
            for path in outputs:
                execute(["magick", "identify", "-ping", str(path)])
            if len(outputs) > 1:
                notes.append(
                    "Multi-image source exported as numbered image files; keep the bundle together."
                )
    finally:
        link.unlink(missing_ok=True)
        (stage / "_icns.png").unlink(missing_ok=True)
    return notes


def media_convert(source, dest, target, stage, execute):
    base = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-n",
        "-threads",
        "2",
        "-filter_threads",
        "2",
        "-filter_complex_threads",
        "2",
        "-protocol_whitelist",
        "file,pipe",
        "-i",
        str(source),
    ]
    notes = [
        "Media export uses the first video/audio stream; subtitles, attachments and extra tracks are not retained. Lossy formats re-encode."
    ]
    if target in FORMATS["audio"]:
        if target == "ape":
            wav = stage / "_audio.wav"
            execute([*base, "-map", "0:a:0", "-vn", "-c:a", "pcm_s24le", str(wav)])
            execute(["mac", str(wav), str(dest), "-c2000"])
            wav.unlink()
        else:
            execute([*base, "-map", "0:a:0", "-vn", *AUDIO[target], str(dest)])
        if target == "alac":
            notes.append(
                "ALAC is Apple Lossless audio in an M4A container; the saved extension is .m4a."
            )
    elif target == "gif":
        execute(
            [
                *base,
                "-an",
                "-filter_complex",
                "[0:v:0]fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                "-loop",
                "0",
                str(dest),
            ]
        )
        notes.append("GIF uses 12 fps and 640-pixel width, with no audio.")
    else:
        args = ["-map", "0:v:0", "-map", "0:a:0?", "-threads", "2"]
        if target == "webm":
            args += ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-c:a", "libopus"]
        elif target == "ogv":
            args += ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis"]
        elif target == "wmv":
            args += ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2", "-f", "asf"]
        elif target in ("mpg", "mpeg", "vob"):
            args += [
                "-c:v",
                "mpeg2video",
                "-q:v",
                "3",
                "-c:a",
                "mp2",
                "-ar",
                "48000",
                "-f",
                "vob" if target == "vob" else "mpeg",
            ]
        elif target == "mxf":
            args += [
                "-vf",
                "scale=1920:1080,fps=25,format=yuv422p",
                "-c:v",
                "mpeg2video",
                "-b:v",
                "50M",
                "-c:a",
                "pcm_s16le",
                "-ar",
                "48000",
                "-f",
                "mxf",
            ]
            notes.append(
                "MXF uses 1080p25 MPEG-2 4:2:2 and 48 kHz PCM; check broadcast specifications separately."
            )
        else:
            args += [
                "-vf",
                "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
                "-c:v",
                "libx264",
                "-preset",
                "fast",
                "-crf",
                "20",
                "-c:a",
                "aac",
                "-b:a",
                "192k",
            ]
            if target in ("mp4", "m4v", "mov"):
                args += ["-movflags", "+faststart", "-f", "mov" if target == "mov" else "mp4"]
            elif target in ("ts", "mts", "m2ts"):
                args += ["-f", "mpegts"]
                if target == "m2ts":
                    args += ["-mpegts_m2ts_mode", "1"]
            elif target == "3gp":
                args += ["-ar", "44100", "-ac", "2", "-f", "3gp"]
            elif target == "flv":
                args += ["-f", "flv"]
        execute(base + args + [str(dest)])
    data = probe(dest)
    required = "audio" if target in FORMATS["audio"] else "video"
    if not any(s["codec_type"] == required for s in data.get("streams", [])):
        raise ValueError(f"Output has no {required} stream")
    return notes


def document_convert(source, fmt, dest, target, stage, execute):
    notes = [
        "Document conversion preserves content structure where supported; exact pagination, fonts and complex layouts may change. DRM-protected ebooks are unsupported."
    ]
    actual, actual_fmt = source, fmt
    if fmt in ("mobi", "azw3"):
        actual, actual_fmt = stage / "_input.epub", "epub"
        execute(["ebook-convert", str(source), str(actual)])
    # Read the document once, retaining packaged media. Embed local linked images
    # explicitly so the writer's sandbox need not access arbitrary paths or URLs.
    ast = json.loads(
        execute(
            [
                "pandoc",
                str(actual),
                "--sandbox",
                "--fail-if-warnings",
                "-f",
                PANDOC[actual_fmt],
                "-t",
                "json",
                "--extract-media",
                "_embedded",
            ]
        )
    )
    media = stage / "media"

    def images(node):
        if isinstance(node, dict):
            if node.get("t") == "Image":
                link = node["c"][2][0]
                parsed = urlsplit(link)
                if parsed.netloc and parsed.scheme not in ("http", "https"):
                    raise ValueError("Document image uses an unsupported remote resource")
                if parsed.scheme in ("http", "https"):
                    if target in ("md", "html", "tex"):
                        notes.append(
                            "External image references remain links; they were not downloaded."
                        )
                        return
                    raise ValueError(
                        "A linked image uses the internet. Save it locally and update the document link before creating a self-contained document."
                    )
                if parsed.scheme == "data":
                    header, encoded = link.split(",", 1)
                    if ";base64" not in header:
                        raise ValueError("Non-base64 image data URI is unsupported")
                    if len(encoded) > guards.MAX_RESOURCE_BYTES * 4 // 3 + 4:
                        raise ValueError("Document image exceeds the 64 MiB safety limit")
                    raw = base64.b64decode(encoded, validate=True)
                    mime = header[5:].split(";", 1)[0]
                else:
                    if parsed.scheme and parsed.scheme != "file":
                        raise ValueError(f"Unsupported image resource scheme: {parsed.scheme}")
                    relative = Path(unquote(parsed.path))
                    candidates = (
                        [relative]
                        if relative.is_absolute()
                        else [stage / relative, source.parent / relative]
                    )
                    resource = guards.local_resource(candidates, [stage, source.parent])
                    mime = run(["file", "-b", "--mime-type", resource], timeout=30).strip()
                    raw = guards.bounded_read(resource, guards.MAX_RESOURCE_BYTES)
                if not mime.startswith("image/"):
                    raise ValueError(f"Document image reference is not an image: {link}")
                if target in ("md", "html", "tex"):
                    import hashlib

                    media.mkdir(exist_ok=True)
                    ext = {
                        "image/jpeg": "jpg",
                        "image/svg+xml": "svg",
                        "image/vnd.microsoft.icon": "ico",
                    }.get(mime, mime.split("/")[-1])
                    name = hashlib.sha256(raw).hexdigest()[:16] + "." + ext
                    (media / name).write_bytes(raw)
                    node["c"][2][0] = "media/" + name
                else:
                    node["c"][2][0] = f"data:{mime};base64," + base64.b64encode(raw).decode("ascii")
            for value in node.values():
                images(value)
        elif isinstance(node, list):
            for value in node:
                images(value)

    images(ast)
    ast_path = stage / "_document.json"
    ast_path.write_text(json.dumps(ast))
    if target in ("mobi", "azw3"):
        intermediate = stage / "_output.epub"
        execute(
            [
                "pandoc",
                str(ast_path),
                "--sandbox",
                "--fail-if-warnings",
                "-f",
                "json",
                "-t",
                "epub",
                "-o",
                str(intermediate),
            ]
        )
        execute(["ebook-convert", str(intermediate), str(dest)])
        with dest.open("rb") as stream:
            stream.seek(60)
            if stream.read(8) != b"BOOKMOBI":
                raise ValueError("Ebook output is not a real MOBI/AZW3 container")
    else:
        args = [
            "pandoc",
            str(ast_path),
            "--sandbox",
            "--fail-if-warnings",
            "-f",
            "json",
            "-t",
            PANDOC[target],
            "--standalone",
            "-o",
            str(dest),
        ]
        if target == "html":
            args += ["--metadata", "pagetitle=" + source.stem]
        execute(args)
        # Ask the reader to parse the result, catching malformed or wrongly named containers.
        execute(
            [
                "pandoc",
                str(dest),
                "--sandbox",
                "-f",
                PANDOC[target],
                "-t",
                "plain",
                "-o",
                os.devnull,
            ]
        )
    for path in (stage / "_input.epub", stage / "_output.epub", ast_path):
        path.unlink(missing_ok=True)
    if (stage / "_embedded").exists():
        shutil.rmtree(stage / "_embedded")
    return notes


def publish_here(stage, parent, label, target):
    """Publish beside sources with exclusive names; bundle only linked/multipart outputs."""
    entries = list(stage.iterdir())
    if not entries or any(p.is_symlink() for p in stage.rglob("*")):
        raise ValueError("Output is empty or contains unexpected symbolic links")
    single = len(entries) == 1 and entries[0].is_file() and not entries[0].is_symlink()
    for number in range(1, 10001):
        suffix = "" if number == 1 else f" ({number})"
        name = (
            f"{entries[0].stem}{suffix}{entries[0].suffix}"
            if single
            else f"{label}-{target}{suffix}"
        )
        final = parent / name
        try:
            if single:
                # Atomic, exclusive publication on APFS and other hard-link filesystems.
                # EEXIST includes directories and dangling symlinks: none are overwritten.
                try:
                    os.link(entries[0], final, follow_symlinks=False)
                except OSError as exc:
                    if exc.errno not in (
                        errno.EPERM,
                        errno.ENOTSUP,
                        errno.EOPNOTSUPP,
                        errno.EXDEV,
                        errno.ENOSYS,
                    ):
                        raise
                    # Some external/File Provider volumes cannot hard-link. Exclusive
                    # creation still prevents overwrites; remove our copy if it fails.
                    output = final.open("xb")
                    try:
                        with output, entries[0].open("rb") as source:
                            while chunk := source.read(1024 * 1024):
                                if CANCEL.is_set():
                                    raise InterruptedError("Conversion cancelled")
                                output.write(chunk)
                    except BaseException:
                        final.unlink()
                        raise
            else:
                # One exclusive directory preserves document media/sidecar references.
                final.mkdir(mode=0o700)
                try:
                    for entry in entries:
                        entry.rename(final / entry.name)
                except BaseException:
                    shutil.rmtree(final)
                    raise
            return final
        except FileExistsError:
            continue
    raise ValueError("Too many existing output names; choose another destination")


def convert_one(info, target, batch, index, source_crs=None, skip_same=False, here=False):
    source = Path(info["path"])
    label = guards.output_name(source.stem)
    final = batch / f"{index + 1:03d}-{label}-{target}"
    result = {
        **info,
        "target": target,
        "success": False,
        "output": None,
        "notes": [],
        "commands": [],
    }
    if info["error"]:
        return result
    if target not in info["targets"]:
        result["error"] = f"Cannot convert {info['category']} to {target.upper()}"
        return result
    equivalent = {"jpeg": "jpg", "yml": "yaml", "mpeg": "mpg"}
    try:
        metadata = source.stat()
        if info.get("fingerprint") != [
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_size,
            metadata.st_mtime_ns,
        ]:
            raise ValueError("Source changed after recognition; select it again")
        if skip_same and equivalent.get(info["format"], info["format"]) == equivalent.get(
            target, target
        ):
            result.update(
                success=True,
                skipped=True,
                error=None,
                notes=["Already in the selected format; source retained without re-encoding."],
            )
            return result
        with tempfile.TemporaryDirectory(prefix=".working-", dir=batch) as tmp:
            stage = Path(tmp)
            extension = "m4a" if target == "alac" else target
            dest = stage / f"{label}.{extension}"

            def execute(args):
                return run(args, cwd=stage, log=result["commands"])

            cat = info["category"]
            if cat == "config":
                structured.convert(source, info["format"], dest, target)
                result["notes"] = [
                    "Configuration values and types were verified by a round trip. Comments, whitespace and key presentation are not retained."
                ]
            elif cat == "geo":
                import geospatial

                result["notes"] = geospatial.convert(
                    source, info["format"], dest, target, stage, execute, source_crs
                )
                for temporary in stage.glob("_input.*"):
                    temporary.unlink(missing_ok=True)
            elif cat == "image":
                result["notes"] = image_convert(
                    source, info["format"], dest, target, stage, execute
                )
            elif cat in ("audio", "video"):
                result["notes"] = media_convert(source, dest, target, stage, execute)
            elif cat == "document":
                result["notes"] = document_convert(
                    source, info["format"], dest, target, stage, execute
                )
            outputs = [p for p in stage.rglob("*") if p.is_file() and not p.name.startswith("_")]
            if not outputs or not any(p.stat().st_size for p in outputs):
                raise ValueError("Conversion produced no readable output")
            if CANCEL.is_set():
                raise InterruptedError("Conversion cancelled")
            if here:
                # Layer audit metadata belongs in the report, not beside a standalone GPKG.
                layers = stage / "layers.json"
                if cat == "geo" and layers.is_file():
                    result["layers"] = json.loads(guards.bounded_read(layers, 1024 * 1024))
                    layers.unlink()
                final = publish_here(stage, batch, label, target)
            else:
                # Destination batches retain their per-job bundles and resource references.
                stage.rename(final)
            result.update(success=True, output=str(final), error=None)
    except Exception as exc:
        result["error"] = str(exc)
    return result


def cancel(signum=None, frame=None):
    # Signal handlers must not take LOCK: the interrupted thread may own it.
    # Each engine monitor observes this flag and escalates TERM to KILL.
    CANCEL.set()


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def main():
    CANCEL.clear()
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--to", choices=[fmt for group in FORMATS.values() for fmt in group])
    parser.add_argument("--plan", type=Path, help="JSON mapping category names to output formats")
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--here", action="store_true", help="Save converted files directly beside their sources"
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        help="Convert Here report storage; defaults to app support/Reports",
    )
    parser.add_argument(
        "--skip-same", action="store_true", help="Skip files already in their selected format"
    )
    parser.add_argument(
        "--source-crs", help="Assign CRS only when it is known to be correct, e.g. EPSG:4326"
    )
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    if not args.files:
        parser.error("Select at least one file")
    if len(args.files) > guards.MAX_FILES:
        parser.error("Select at most 1000 files per batch")
    if args.here and args.output:
        parser.error("Choose either --here or --output")
    files = list(dict.fromkeys(str(Path(p).expanduser().resolve()) for p in args.files))
    # Finder selections often include all Shapefile components: don't convert those separately.
    shp_stems = {
        (str(Path(p).parent), Path(p).stem.lower())
        for p in files
        if Path(p).suffix.lower() == ".shp"
    }
    sidecars = {".shx", ".dbf", ".prj", ".cpg", ".sbn", ".sbx", ".qix"}
    files = [
        p
        for p in files
        if not (
            Path(p).suffix.lower() in sidecars
            and (str(Path(p).parent), Path(p).stem.lower()) in shp_stems
        )
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        infos = list(pool.map(inspect, files))
    if args.inspect:
        emit({"files": infos, "formats": FORMATS})
        return 130 if CANCEL.is_set() else 0
    if not args.to and not args.plan:
        parser.error("Use --to FORMAT or --plan PLAN.json")
    if args.plan:
        try:
            plan = json.loads(guards.bounded_read(args.plan, 64 * 1024))
            if not isinstance(plan, dict) or any(
                k not in FORMATS
                or not isinstance(v, str)
                or v not in FORMATS[k] + (FORMATS["audio"] if k == "video" else [])
                for k, v in plan.items()
            ):
                raise ValueError("Plan must map known categories to supported format names")
        except (OSError, ValueError) as exc:
            parser.error(str(exc))
    else:
        plan = {}
    destination = (args.output or Path(files[0]).parent).expanduser().absolute()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H-%M-%S")
    batches = {}
    report_paths = {}
    created = []
    parents = list(
        dict.fromkeys(Path(info["path"]).parent if args.here else destination for info in infos)
    )
    if args.here and any(not p.is_dir() for p in parents):
        raise ValueError("A source folder is unavailable; choose a destination folder instead")
    try:
        if args.here:
            report_root = (
                (
                    args.reports_dir
                    or Path.home() / "Library/Application Support/UltraConvert/Reports"
                )
                .expanduser()
                .absolute()
            )
            report_root.mkdir(parents=True, exist_ok=True)
            report_folder = report_root / f"Converted {stamp} {uuid.uuid4().hex[:8]}"
            report_folder.mkdir(exist_ok=False)
            created.append(report_folder)
        for parent in parents:
            if args.here:
                batches[parent] = parent
                name = (
                    "conversion-report.json"
                    if len(parents) == 1
                    else f"conversion-report-{len(report_paths) + 1:03d}.json"
                )
                report_paths[parent] = report_folder / name
            else:
                parent.mkdir(parents=True, exist_ok=True)
                batch = parent / f"Converted {stamp} {uuid.uuid4().hex[:8]}"
                batch.mkdir(exist_ok=False)
                created.append(batch)
                batches[parent] = batch
                report_paths[parent] = batch / "conversion-report.json"
    except OSError:
        for batch in created:
            batch.rmdir()
        raise
    first_batch = next(iter(batches.values()))
    emit(
        {
            "event": "start",
            "total": len(infos),
            "output": str(first_batch),
            "outputs": list(map(str, batches.values())),
        }
    )
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {
            pool.submit(
                convert_one,
                info,
                args.to or plan.get(info["category"], ""),
                batches[Path(info["path"]).parent if args.here else destination],
                i,
                args.source_crs,
                args.skip_same,
                args.here,
            ): i
            for i, info in enumerate(infos)
        }
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            emit(
                {
                    "event": "file",
                    "completed": len(results),
                    "total": len(infos),
                    "result": {k: v for k, v in result.items() if k not in ("commands", "targets")},
                }
            )
    report = {
        "date": datetime.datetime.now().astimezone().isoformat(),
        "output": str(first_batch),
        "outputs": list(map(str, batches.values())),
        "reports": list(map(str, report_paths.values())),
        "result_files": [r["output"] for r in results if r["output"]],
        "placement": "here" if args.here else "destination",
        "success": sum(r["success"] and not r.get("skipped") for r in results),
        "skipped": sum(bool(r.get("skipped")) for r in results),
        "failed": sum(not r["success"] for r in results),
        "cancelled": CANCEL.is_set(),
        "results": sorted(results, key=lambda r: r["path"]),
    }
    for parent, batch in batches.items():
        saved = dict(
            report,
            output=str(batch),
            results=[
                r
                for r in report["results"]
                if (Path(r["path"]).parent if args.here else destination) == parent
            ],
        )
        saved["overall"] = {
            key: report[key] for key in ("success", "skipped", "failed", "cancelled")
        }
        saved["success"] = sum(r["success"] and not r.get("skipped") for r in saved["results"])
        saved["skipped"] = sum(bool(r.get("skipped")) for r in saved["results"])
        saved["failed"] = sum(not r["success"] for r in saved["results"])
        with report_paths[parent].open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(saved, indent=2, ensure_ascii=False) + "\n")
    report["results"] = [
        {k: v for k, v in r.items() if k not in ("commands", "targets")} for r in report["results"]
    ]
    emit({"event": "complete", **report})
    return 130 if CANCEL.is_set() else 1 if report["failed"] else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as exc:
        print(f"UltraConvert: {exc}", file=sys.stderr)
        sys.exit(2)
