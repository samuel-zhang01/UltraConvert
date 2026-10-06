"""OGR conversion with every nonempty layer retained and sidecars kept together."""

import json
import re

from defusedxml import ElementTree
from osgeo import gdal, ogr, osr

from guards import MAX_TEXT_BYTES, bounded_read, validate_archive, validate_xml

gdal.UseExceptions()
ogr.UseExceptions()
for key, value in {
    "LIBKML_EXTERNAL_STYLE": "NO",
    "LIBKML_RESOLVE_STYLE": "NO",
    "GML_DOWNLOAD_SCHEMA": "NO",
    "GML_SKIP_RESOLVE_ELEMS": "ALL",
    "PROJ_NETWORK": "OFF",
}.items():
    gdal.SetConfigOption(key, value)

DRIVERS = {
    "geojson": "GeoJSON",
    "gpkg": "GPKG",
    "shp": "ESRI Shapefile",
    "kml": "LIBKML",
    "kmz": "LIBKML",
    "gpx": "GPX",
    "gml": "GML",
}


def safe_name(value):
    return re.sub(r"[^\w.-]+", "_", value).strip(".")[:120] or "layer"


def from_wkt(source, stage, source_crs):
    result = {"type": "FeatureCollection", "features": []}
    # Attributes exported alongside our WKT files can be restored on import.
    attrs_path = source.with_suffix(".attributes.json")
    attrs = json.loads(bounded_read(attrs_path)) if attrs_path.exists() else []
    srid = None
    lines = [
        line.strip()
        for line in bounded_read(source).decode("utf-8-sig").splitlines()
        if line.strip()
    ]
    if not lines:
        raise ValueError("WKT file has no geometries")
    if attrs and len(attrs) != len(lines):
        raise ValueError("WKT attributes sidecar does not match geometry count")
    for index, line in enumerate(lines):
        if line.upper().startswith("SRID="):
            prefix, line = line.split(";", 1)
            current = int(prefix[5:])
            if srid is not None and srid != current:
                raise ValueError("WKT geometries use different coordinate systems")
            srid = current
        geometry = ogr.CreateGeometryFromWkt(line)
        if geometry is None:
            raise ValueError(f"Invalid WKT geometry on line {index + 1}")
        result["features"].append(
            {
                "type": "Feature",
                "geometry": json.loads(geometry.ExportToJson()),
                "properties": attrs[index] if attrs else {},
            }
        )
    crs = f"EPSG:{srid}" if srid else source_crs
    prj = source.with_suffix(".prj")
    if not crs and prj.exists():
        crs = bounded_read(prj, 64 * 1024).decode("utf-8-sig").strip()
    if not crs:
        raise ValueError(
            "WKT has no CRS. Set the WKT input CRS in the app or use --source-crs EPSG:4326 (only if correct)"
        )
    ref = osr.SpatialReference()
    ref.SetFromUserInput(crs)
    result["crs"] = {"type": "name", "properties": {"name": ref.ExportToWkt()}}
    path = stage / "_input.geojson"
    path.write_text(json.dumps(result))
    return path


def convert(source, source_fmt, dest, target, stage, run, source_crs=None):
    actual = from_wkt(source, stage, source_crs) if source_fmt == "wkt" else source
    if source_fmt in ("gml", "kml", "gpx"):
        if source.stat().st_size > MAX_TEXT_BYTES:
            raise ValueError("GIS XML exceeds the 64 MiB safety limit")
        with source.open("rb") as stream:
            validate_xml(stream)
    if source_fmt == "kmz":
        import zipfile

        validate_archive(source)
        with zipfile.ZipFile(source) as archive:
            for entry in archive.infolist():
                if entry.filename.lower().endswith(".kml"):
                    if entry.file_size > MAX_TEXT_BYTES:
                        raise ValueError("KMZ KML exceeds the 64 MiB safety limit")
                    with archive.open(entry) as stream:
                        validate_xml(stream)
    if source_fmt == "gml":
        # OGR can create .gfs caches even for a read-only open. Stage the input so
        # it never writes beside the user's original; retain a local XSD if any.
        import shutil

        actual = stage / "_input.gml"
        shutil.copy2(source, actual)
        xsd = source.with_suffix(".xsd")
        if xsd.is_file():
            validate_xml(xsd)
            schema = bounded_read(xsd)
            for node in ElementTree.fromstring(schema).iter():
                kind = node.tag.rsplit("}", 1)[-1]
                location = node.get("schemaLocation")
                # OGR-generated schemas refer to the built-in GML namespace.
                # GDAL schema downloads remain disabled; arbitrary imports/includes fail.
                standard_gml = (
                    kind == "import"
                    and node.get("namespace")
                    in {
                        "http://www.opengis.net/gml",
                        "http://www.opengis.net/gml/3.2",
                        "http://www.opengis.net/gmlsf/2.0",
                    }
                    and location
                    in {
                        "http://schemas.opengis.net/gml/3.1.1/base/gml.xsd",
                        "http://schemas.opengis.net/gml/3.2.1/gml.xsd",
                        "https://schemas.opengis.net/gml/3.1.1/base/gml.xsd",
                        "https://schemas.opengis.net/gml/3.2.1/gml.xsd",
                        "http://schemas.opengis.net/gmlsfProfile/2.0/gmlsfLevels.xsd",
                        "https://schemas.opengis.net/gmlsfProfile/2.0/gmlsfLevels.xsd",
                    }
                )
                if kind in {"include", "import", "redefine"} and location and not standard_gml:
                    raise ValueError(
                        "External XSD includes/imports are unsupported; use a self-contained schema"
                    )
            actual.with_suffix(".xsd").write_bytes(schema)
    if source_fmt == "shp":
        companions = {
            p.suffix.lower()
            for p in source.parent.iterdir()
            if p.stem.lower() == source.stem.lower()
        }
        if not {".shx", ".dbf"}.issubset(companions):
            raise ValueError("Shapefile needs matching .shx and .dbf files in the same folder")
    driver_names = ["GeoJSON"] if source_fmt == "wkt" else [DRIVERS[source_fmt]]
    dataset = gdal.OpenEx(
        str(actual), gdal.OF_VECTOR | gdal.OF_READONLY, allowed_drivers=driver_names
    )
    layers = [dataset.GetLayer(i) for i in range(dataset.GetLayerCount())]
    layers = [layer for layer in layers if layer.GetFeatureCount() != 0]
    if not layers:
        raise ValueError("No nonempty vector layers found")
    names = [layer.GetName() for layer in layers]
    counts = {layer.GetName(): layer.GetFeatureCount() for layer in layers}
    unknown = [layer.GetName() for layer in layers if not layer.GetSpatialRef()]
    if source_crs and unknown and len(unknown) != len(layers):
        raise ValueError(
            "Dataset mixes known and unknown coordinate systems; assign missing layer CRS separately before batch conversion"
        )
    override_crs = source_crs if source_fmt == "wkt" or len(unknown) == len(layers) else None
    notices = []
    if target == "wkt":
        notices.append(
            "WKT geometries use .attributes.json and .prj sidecars to retain attributes and CRS; keep them together."
        )
        for index, layer in enumerate(layers):
            path = (
                dest
                if len(layers) == 1
                else dest.with_name(f"{dest.stem}-{index + 1}-{safe_name(layer.GetName())}.wkt")
            )
            geometries, attrs = [], []
            layer.ResetReading()
            for feature in layer:
                geometry = feature.GetGeometryRef()
                if geometry is None:
                    raise ValueError("WKT cannot represent a feature with null geometry")
                geometries.append(geometry.ExportToIsoWkt())
                attrs.append(json.loads(feature.ExportToJson())["properties"])
            path.write_text("\n".join(geometries) + "\n")
            path.with_suffix(".attributes.json").write_text(json.dumps(attrs, indent=2))
            if layer.GetSpatialRef():
                path.with_suffix(".prj").write_text(layer.GetSpatialRef().ExportToWkt())
        return notices
    if target in ("kml", "kmz", "gpx", "geojson"):
        if unknown and not source_crs:
            raise ValueError(
                f"Cannot export to {target.upper()} without a CRS. Unknown layers: {', '.join(unknown)}"
            )
    if target == "gpx":
        allowed = {ogr.wkbPoint, ogr.wkbLineString, ogr.wkbMultiLineString}
        for layer in layers:
            for feature in layer:
                geom = feature.GetGeometryRef()
                if geom and ogr.GT_Flatten(geom.GetGeometryType()) not in allowed:
                    raise ValueError(
                        "GPX supports points and tracks/routes; polygon geometry cannot be preserved"
                    )
        notices.append(
            "GPX represents points/tracks/routes in WGS84; extra fields use GPX extensions."
        )
    if target == "shp":
        notices.append(
            "Shapefile field names may shorten to 10 characters; nested types, dates and geometry types have legacy limits."
        )
    if target in ("kml", "kmz"):
        notices.append(
            "KML/KMZ export vector features in WGS84; map styling, attachments and overlays may not survive."
        )
    driver = DRIVERS[target]
    if not gdal.GetDriverByName(driver):
        raise ValueError(f"GDAL driver {driver} is unavailable; install Homebrew gdal with libkml")
    combined = target in ("gpkg", "kml", "kmz")
    groups = (
        [(dest, names)]
        if combined
        else [
            (
                dest
                if len(names) == 1
                else dest.with_name(f"{dest.stem}-{i + 1}-{safe_name(name)}.{target}"),
                [name],
            )
            for i, name in enumerate(names)
        ]
    )
    dataset = None
    for path, group in groups:
        args = ["ogr2ogr", "-f", driver]
        if override_crs:
            args += [
                "-s_srs" if target in ("kml", "kmz", "gpx", "geojson") else "-a_srs",
                override_crs,
            ]
        if target in ("kml", "kmz", "gpx", "geojson"):
            args += ["-t_srs", "EPSG:4326"]
        if target == "gpx":
            args += ["-dsco", "GPX_USE_EXTENSIONS=YES"]
        if target == "shp":
            args += ["-lco", "ENCODING=UTF-8"]
        run([*args, str(path), str(actual), *group])
        output = gdal.OpenEx(str(path), gdal.OF_VECTOR | gdal.OF_READONLY, allowed_drivers=[driver])
        actual_count = sum(
            output.GetLayer(i).GetFeatureCount() for i in range(output.GetLayerCount())
        )
        expected = sum(counts[name] for name in group)
        # GPX can expose synthetic track_points as well as tracks.
        if target != "gpx" and actual_count != expected:
            raise ValueError(
                f"Feature count changed during export ({expected} → {actual_count}); output refused"
            )
        if target == "gpx" and actual_count < expected:
            raise ValueError("GPX export lost features; output refused")
        output = None
    (stage / "layers.json").write_text(
        json.dumps({"source_layers": counts, "target": target, "notes": notices}, indent=2)
    )
    for temporary in stage.glob("_input.*"):
        temporary.unlink(missing_ok=True)
    return notices
