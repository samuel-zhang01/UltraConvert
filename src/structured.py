"""Typed configuration conversion. Refuse silent coercion or duplicate keys."""

import datetime
import json
import math
import plistlib
import tomllib

import tomli_w
import yaml

from guards import MAX_CONFIG_BYTES, MAX_DEPTH, MAX_NODES, bounded_read


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate configuration key: {key!r}")
        result[key] = value
    return result


class StrictLoader(yaml.SafeLoader):
    def __init__(self, stream):
        super().__init__(stream)
        self.aliases = 0
        self.depth = 0

    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            self.aliases += 1
            if self.aliases > 128:
                raise ValueError("Too many YAML aliases")
        self.depth += 1
        try:
            if self.depth > MAX_DEPTH:
                raise ValueError("Configuration nesting exceeds the safety limit")
            return super().compose_node(parent, index)
        finally:
            self.depth -= 1


def yaml_mapping(loader, node):
    loader.flatten_mapping(node)
    return unique_pairs(loader.construct_pairs(node, deep=True))


StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, yaml_mapping)


def load(path, fmt):
    raw = bounded_read(path, MAX_CONFIG_BYTES)
    if fmt == "plist":
        return plistlib.loads(raw)
    text = raw.decode("utf-8-sig")
    if fmt == "json":

        def bad_constant(value):
            raise ValueError(f"Nonstandard JSON number: {value}")

        return json.loads(text, object_pairs_hook=unique_pairs, parse_constant=bad_constant)
    if fmt in ("yaml", "yml"):
        # StrictLoader extends SafeLoader and bounds aliases/depth.
        return yaml.load(text, Loader=StrictLoader)  # nosec B506
    if fmt == "toml":
        return tomllib.loads(text)
    raise ValueError(f"Unsupported configuration format: {fmt}")


def signature(value, seen=None, budget=None, depth=0):
    """Check types and cycles, then compare a round trip without int/float coercion."""
    seen = set() if seen is None else seen
    budget = [MAX_NODES] if budget is None else budget
    budget[0] -= 1
    if budget[0] < 0 or depth > MAX_DEPTH:
        raise ValueError("Configuration expansion or nesting exceeds the safety limit")
    if isinstance(value, (dict, list)):
        if id(value) in seen:
            raise ValueError("Recursive YAML aliases cannot be converted safely")
        seen.add(id(value))
        try:
            if isinstance(value, dict):
                if any(not isinstance(k, str) for k in value):
                    raise ValueError("Configuration keys must be strings")
                return (
                    "dict",
                    sorted((k, signature(v, seen, budget, depth + 1)) for k, v in value.items()),
                )
            return ("list", [signature(v, seen, budget, depth + 1) for v in value])
        finally:
            seen.remove(id(value))
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("Non-finite numbers are not portable between configuration formats")
    if isinstance(value, (datetime.date, datetime.datetime, bytes)):
        return (type(value).__name__, repr(value))
    if value is None or type(value) in (bool, int, float, str):
        return (type(value).__name__, value)
    raise ValueError(f"Unsupported configuration type: {type(value).__name__}")


def convert(source, source_fmt, dest, target):
    data = load(source, source_fmt)
    before = signature(data)
    try:
        if target == "json":
            dest.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n")
        elif target in ("yaml", "yml"):
            dest.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
        elif target == "plist":
            dest.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False))
        elif target == "toml":
            if not isinstance(data, dict):
                raise ValueError("TOML requires a table/dictionary at the root")
            dest.write_text(tomli_w.dumps(data))
        else:
            raise ValueError(f"Unsupported destination: {target}")
        if signature(load(dest, target)) != before:
            raise ValueError("The destination changes data types; conversion was refused")
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError(f"Cannot preserve configuration data in {target.upper()}: {exc}") from exc
