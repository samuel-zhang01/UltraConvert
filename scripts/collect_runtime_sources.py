"""Collect checksum-pinned Homebrew sources for a development bundle.

The report remains incomplete: Calibre's full build tree, source resources not
expressed as archive/checksum pairs, static dependencies and notices need review.
"""

import argparse
import concurrent.futures
import hashlib
import json
import re
import shutil
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit


def https_url(url):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Only credential-free HTTPS source URLs are allowed")
    return url


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        https_url(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def recipe_sources(recipe):
    current = None
    sources = []
    for line in recipe.splitlines():
        url = re.match(r'\s*url "([^"]+)"', line)
        if url:
            current = url[1]
        digest = re.match(r'\s*sha256 "([a-f0-9]{64})"', line)
        if digest and current:
            if current.startswith("https://") and "#{" not in current:
                sources.append({"url": current, "sha256": digest[1]})
            current = None
    return sources


def download(entry, destination):
    digest = entry["sha256"]
    filename = Path(urlsplit(entry["url"]).path).name or "source.archive"
    path = destination / (digest[:16] + "-" + filename)
    try:
        https_url(entry["url"])
        if path.exists():
            with path.open("rb") as stream:
                cached = hashlib.file_digest(stream, "sha256").hexdigest()
            if cached == digest:
                return {**entry, "file": path.name, "verified": True}
        temporary = path.with_suffix(path.suffix + ".partial")
        with (
            urllib.request.build_opener(HTTPSRedirects()).open(
                entry["url"], timeout=30
            ) as response,
            temporary.open("wb") as stream,
        ):
            actual = hashlib.sha256()
            total = 0
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > 1024 * 1024 * 1024:
                    raise ValueError("Source archive exceeded 1 GiB download bound")
                actual.update(chunk)
                stream.write(chunk)
        if actual.hexdigest() != digest:
            raise ValueError("Source archive checksum mismatch")
        temporary.replace(path)
        return {**entry, "file": path.name, "verified": True}
    except (OSError, ValueError) as error:
        return {**entry, "verified": False, "error": str(error)[:300]}


def collect(app, destination, fetch=False):
    third_party = app.resolve() / "Contents/Resources/ThirdParty"
    inventory = json.loads((third_party / "inventory.json").read_text())
    destination.mkdir(parents=True, exist_ok=True)
    recipes = destination / "recipes"
    if not recipes.exists():
        shutil.copytree(third_party / "Homebrew", recipes)
    entries = []
    missing = []
    for formula in inventory["formulae"]:
        recipe = recipes / formula["name"] / (formula["name"] + ".rb")
        found = recipe_sources(recipe.read_text()) if recipe.exists() else []
        if not found:
            missing.append(formula["name"])
        entries.extend({"formula": formula["name"], **entry} for entry in found)
    archives = destination / "archives"
    archives.mkdir(exist_ok=True)
    if fetch:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            entries = list(pool.map(lambda entry: download(entry, archives), entries))
    report = {
        "schema": 1,
        "source_archives": entries,
        "formulas_without_pinned_archive": missing,
        "verified_archive_count": sum(entry.get("verified", False) for entry in entries),
        "corresponding_source_complete": False,
        "remaining": [
            "Review recipes/resources, static and generated dependencies for complete corresponding source",
            "Calibre and its bundled third-party build sources",
            "Complete licence/notice inventory and redistribution review",
        ],
    }
    (destination / "SOURCE-INVENTORY.json").write_text(json.dumps(report, indent=2) + "\n")
    return {
        "planned_archives": len(entries),
        "verified_archives": report["verified_archive_count"],
        "unresolved_formulas": len(missing),
        "corresponding_source_complete": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    print(json.dumps(collect(args.app, args.output, args.download)))
