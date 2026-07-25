#!/usr/bin/env python3
"""Validate JamReader string catalogs without requiring Xcode."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
LOCALIZABLE_CATALOG = PROJECT_ROOT / "JamReader" / "Localizable.xcstrings"
INFO_PLIST_CATALOG = PROJECT_ROOT / "JamReader" / "InfoPlist.xcstrings"
PROJECT_FILE = PROJECT_ROOT / "JamReader.xcodeproj" / "project.pbxproj"

SOURCE_LANGUAGE = "en"
TARGET_LANGUAGES = ("zh-Hans", "zh-Hant-TW", "ja")
REQUIRED_REGIONS = {SOURCE_LANGUAGE, *TARGET_LANGUAGES}

PLACEHOLDER_PATTERN = re.compile(
    r"%(?:(?P<position>\d+)\$)?"
    r"[-+0 #']*\d*(?:\.\d+)?"
    r"(?P<length>[hlLzjtq]*)"
    r"(?P<conversion>[diuoxXfFeEgGaAcCsSp@%])"
)


def load_catalog(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path.relative_to(PROJECT_ROOT)} is not valid JSON: {error}")


def fail(message: str) -> None:
    print(f"[check_localizations] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def string_unit(entry: dict, language: str) -> dict | None:
    localization = entry.get("localizations", {}).get(language, {})
    unit = localization.get("stringUnit")
    return unit if isinstance(unit, dict) else None


def string_unit_value(entry: dict, language: str) -> str | None:
    unit = string_unit(entry, language)
    if unit is None:
        return None
    value = unit.get("value")
    return value if isinstance(value, str) else None


def placeholder_signature(value: str) -> list[tuple[int, str]]:
    """Return argument positions and exact printf conversion types.

    Translators may reorder placeholders only by using explicit positions. Keeping
    the length modifier and conversion prevents unsafe substitutions such as
    changing `%u` into `%lld` merely because both happen to be integers.
    """

    if "%" in PLACEHOLDER_PATTERN.sub("", value):
        raise ValueError("contains an invalid or unescaped percent sign")

    placeholders: list[tuple[int, str]] = []
    next_implicit_position = 1
    for match in PLACEHOLDER_PATTERN.finditer(value):
        conversion = match.group("conversion")
        if conversion == "%":
            continue

        explicit_position = match.group("position")
        if explicit_position is None:
            position = next_implicit_position
            next_implicit_position += 1
        else:
            position = int(explicit_position)

        placeholders.append(
            (position, f"{match.group('length')}{conversion}")
        )

    return sorted(placeholders)


def validate_catalog(
    path: Path,
    *,
    required_languages: tuple[str, ...],
    require_explicit_source: bool,
) -> int:
    catalog = load_catalog(path)
    relative_path = path.relative_to(PROJECT_ROOT)

    if catalog.get("sourceLanguage") != SOURCE_LANGUAGE:
        fail(f"{relative_path} must use {SOURCE_LANGUAGE} as sourceLanguage")

    strings = catalog.get("strings")
    if not isinstance(strings, dict) or not strings:
        fail(f"{relative_path} does not contain any strings")

    translated_key_count = 0
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            fail(f"{relative_path}: {key!r} has an invalid entry")
        if entry.get("extractionState") == "stale":
            fail(f"{relative_path}: {key!r} is stale")
        if entry.get("shouldTranslate") is False:
            continue

        source_value = string_unit_value(entry, SOURCE_LANGUAGE)
        if source_value is None:
            if require_explicit_source:
                fail(f"{relative_path}: {key!r} is missing {SOURCE_LANGUAGE}")
            source_value = key

        try:
            source_placeholders = placeholder_signature(source_value)
        except ValueError as error:
            fail(f"{relative_path}: {key!r} source format {error}")
        for language in required_languages:
            translated_unit = string_unit(entry, language)
            translated_value = string_unit_value(entry, language)
            if translated_value is None or not translated_value.strip():
                fail(f"{relative_path}: {key!r} is missing {language}")
            if translated_unit.get("state") != "translated":
                fail(f"{relative_path}: {key!r} is not marked translated in {language}")

            try:
                translated_placeholders = placeholder_signature(translated_value)
            except ValueError as error:
                fail(f"{relative_path}: {key!r} {language} format {error}")
            if translated_placeholders != source_placeholders:
                fail(
                    f"{relative_path}: {key!r} has mismatched placeholders in {language} "
                    f"({source_placeholders} != {translated_placeholders})"
                )

        translated_key_count += 1

    return translated_key_count


def validate_known_regions() -> None:
    try:
        project_text = PROJECT_FILE.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"Unable to read {PROJECT_FILE.relative_to(PROJECT_ROOT)}: {error}")

    known_region_blocks = re.findall(
        r"knownRegions\s*=\s*\((.*?)\);",
        project_text,
        flags=re.DOTALL,
    )
    if not known_region_blocks:
        fail("Xcode project does not contain a knownRegions block")

    known_regions = {
        token.strip().strip('"')
        for block in known_region_blocks
        for token in block.split(",")
        if token.strip()
    }
    missing_regions = sorted(REQUIRED_REGIONS - known_regions)
    if missing_regions:
        fail(f"Xcode project is missing known regions: {', '.join(missing_regions)}")


def main() -> None:
    validate_known_regions()
    app_key_count = validate_catalog(
        LOCALIZABLE_CATALOG,
        required_languages=TARGET_LANGUAGES,
        require_explicit_source=False,
    )
    info_key_count = validate_catalog(
        INFO_PLIST_CATALOG,
        required_languages=(SOURCE_LANGUAGE, *TARGET_LANGUAGES),
        require_explicit_source=True,
    )
    print(
        "[check_localizations] OK: "
        f"{app_key_count} app strings and {info_key_count} Info.plist strings cover "
        f"{SOURCE_LANGUAGE}, {', '.join(TARGET_LANGUAGES)}."
    )


if __name__ == "__main__":
    main()
