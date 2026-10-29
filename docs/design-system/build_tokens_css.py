#!/usr/bin/env python3
"""Regenerate tokens.css from tokens.json (used only by the HTML previews).

Run from anywhere:  python3 docs/design-system/build_tokens_css.py
tokens.json is the single source of truth; never edit tokens.css by hand.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
tokens = json.loads((ROOT / "tokens.json").read_text(encoding="utf-8"))
themes = [t["id"] for t in tokens["color"]["themes"]]


def value(token, theme):
    v = token["value"]
    if isinstance(v, str):
        return v
    return v.get(theme, v[themes[0]])


def alias(v):
    return f"var(--{v[1:-1]})" if v.startswith("{") and v.endswith("}") else v


lines = ["/* JamReader — generated from tokens.json */"]
first = themes[0]
lines.append(f':root, [data-theme="{first}"] {{')
for t in tokens["color"]["tokens"]:
    lines.append(f"  --{t['name']}: {alias(value(t, first))};")
for t in tokens.get("shadow", {}).get("tokens", []):
    lines.append(f"  --{t['name']}: {t['value']};")
lines.append("}")
for theme in themes[1:]:
    lines.append(f'[data-theme="{theme}"] {{')
    for t in tokens["color"]["tokens"]:
        lines.append(f"  --{t['name']}: {alias(value(t, theme))};")
    lines.append("}")
lines.append(":root {")
for family in ("spacing", "radius", "size"):
    for t in tokens.get(family, {}).get("tokens", []):
        lines.append(f"  --{t['name']}: {t['value']};")
for key, stack in tokens["type"]["families"].items():
    lines.append(f"  --font-{key}: {stack};")
lines.append("}")
for group in tokens["type"]["groups"]:
    for s in group["styles"]:
        fam = s.get("family", group["family"])
        lines.append(
            f".{s['name']} {{ font-family: var(--font-{fam}); font-size: {s['fontSize']}; "
            f"line-height: {s['lineHeight']}; font-weight: {s['fontWeight']}; }}"
        )
(ROOT / "tokens.css").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"wrote {ROOT / 'tokens.css'}")
