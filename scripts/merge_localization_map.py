#!/usr/bin/env python3
"""Merge a complete key-to-translation JSON map into Localizable.xcstrings."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from check_localizations import SOURCE_LANGUAGE, placeholder_signature, string_unit_value


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = PROJECT_ROOT / "JamReader" / "Localizable.xcstrings"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("language", help="BCP-47 language identifier, for example ja")
    parser.add_argument("translation_map", type=Path, help="JSON object keyed by catalog key")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise SystemExit(f"{path} must contain a JSON object")
    return value


def main() -> None:
    arguments = parse_arguments()
    catalog_path = arguments.catalog.resolve()
    translations = load_json(arguments.translation_map.resolve())
    catalog = load_json(catalog_path)
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise SystemExit(f"{catalog_path} does not contain a strings object")

    required_keys = {
        key
        for key, entry in strings.items()
        if isinstance(entry, dict) and entry.get("shouldTranslate") is not False
    }
    provided_keys = set(translations)
    missing_keys = sorted(required_keys - provided_keys)
    extra_keys = sorted(provided_keys - required_keys)
    if missing_keys or extra_keys:
        if missing_keys:
            print("Missing keys:")
            print("\n".join(missing_keys))
        if extra_keys:
            print("Unexpected keys:")
            print("\n".join(extra_keys))
        raise SystemExit(1)

    for key in sorted(required_keys):
        translated_value = translations[key]
        if not isinstance(translated_value, str) or not translated_value.strip():
            raise SystemExit(f"Translation for {key!r} must be a non-empty string")
        entry = strings[key]
        source_value = string_unit_value(entry, SOURCE_LANGUAGE) or key
        try:
            source_placeholders = placeholder_signature(source_value)
            translated_placeholders = placeholder_signature(translated_value)
        except ValueError as error:
            raise SystemExit(f"Translation for {key!r} {error}") from error
        if translated_placeholders != source_placeholders:
            raise SystemExit(
                f"Translation for {key!r} has mismatched placeholders: "
                f"{source_placeholders} != {translated_placeholders}"
            )
        localizations = entry.setdefault("localizations", {})
        localizations[arguments.language] = {
            "stringUnit": {
                "state": "translated",
                "value": translated_value,
            }
        }

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=catalog_path.parent,
        prefix=f".{catalog_path.name}.",
        suffix=".tmp",
        delete=False,
    ) as temporary_file:
        json.dump(catalog, temporary_file, ensure_ascii=False, indent=2)
        temporary_file.write("\n")
        temporary_path = Path(temporary_file.name)

    os.replace(temporary_path, catalog_path)
    print(
        f"Merged {len(required_keys)} {arguments.language} translations into "
        f"{catalog_path.relative_to(PROJECT_ROOT)}"
    )


if __name__ == "__main__":
    main()
