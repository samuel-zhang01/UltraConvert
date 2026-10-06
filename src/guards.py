"""Input limits and safe local resource handling for conversion engines."""

import stat
import zipfile
from pathlib import Path, PurePosixPath

from defusedxml import ElementTree

MAX_CONFIG_BYTES = 32 * 1024 * 1024
MAX_TEXT_BYTES = 64 * 1024 * 1024
MAX_RESOURCE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 10_000
MAX_NODES = 200_000
MAX_DEPTH = 100
MAX_FILES = 1_000


def bounded_read(path, limit=MAX_TEXT_BYTES):
    with Path(path).open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"File exceeds the {limit // (1024 * 1024)} MiB safety limit")
    return data


def validate_archive(path):
    """Reject traversal, symlinks, encryption and expansion bombs before engines."""
    if Path(path).stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValueError("Document/archive exceeds the 512 MiB safety limit")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) > MAX_ARCHIVE_ENTRIES:
            raise ValueError("Archive has too many entries")
        names = set()
        total = 0
        for entry in entries:
            name = entry.filename
            member = PurePosixPath(name)
            if member.is_absolute() or ".." in member.parts or "\\" in name or "\x00" in name:
                raise ValueError("Archive contains an unsafe member path")
            if name in names:
                raise ValueError("Archive contains duplicate member paths")
            names.add(name)
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Archive contains a symbolic link")
            if entry.flag_bits & 1:
                raise ValueError("Encrypted archives are unsupported")
            total += entry.file_size
            if (
                name.lower().endswith((".xml", ".kml", ".xhtml", ".html"))
                and entry.file_size > MAX_TEXT_BYTES
            ):
                raise ValueError("Archive XML/text member exceeds the 64 MiB safety limit")
            if total > MAX_ARCHIVE_BYTES:
                raise ValueError("Archive expansion exceeds the 512 MiB safety limit")
        return entries


def validate_xml(stream):
    """Stream XML without retaining the tree; prohibit DTD/entity expansion."""
    for _, element in ElementTree.iterparse(stream, events=("end",), forbid_dtd=True):
        element.clear()


def local_resource(link_path, roots):
    for candidate in link_path:
        resolved = candidate.resolve()
        if resolved.is_file() and any(resolved.is_relative_to(root.resolve()) for root in roots):
            return resolved
    raise ValueError(
        "Linked image is missing or outside the source folder; copy it beside the document"
    )


def output_name(value):
    import re

    value = re.sub(r"[^\w .-]", "_", value).strip(" .")
    return value.encode("utf-8")[:80].decode("utf-8", errors="ignore") or "file"
