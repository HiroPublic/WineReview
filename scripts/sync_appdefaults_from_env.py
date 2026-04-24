#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


TARGET_KEYS = ("WINE_REVIEW_TEMPLATE_1", "WINE_REVIEW_TEMPLATE_2")


def parse_env(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    lines = text.splitlines()
    index = 0

    while index < len(lines):
        line = lines[index].strip()
        index += 1

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if value.startswith('"'):
            while not value.endswith('"') and index < len(lines):
                value += "\n" + lines[index]
                index += 1

        if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
            value = value[1:-1]

        result[key] = unescape(value)

    return result


def unescape(value: str) -> str:
    return (
        value.replace("\\n", "\n")
        .replace("\\r", "\r")
        .replace("\\t", "\t")
        .replace('\\"', '"')
    )


def escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sync_appdefaults_from_env.py <source_env> <target_appdefaults>", file=sys.stderr)
        return 1

    source_path = Path(sys.argv[1])
    target_path = Path(sys.argv[2])

    if not source_path.exists() or not target_path.exists():
        return 0

    source_values = parse_env(source_path.read_text(encoding="utf-8"))
    target_values = parse_env(target_path.read_text(encoding="utf-8"))

    changed = False
    for key in TARGET_KEYS:
        if key in source_values and target_values.get(key) != source_values[key]:
            target_values[key] = source_values[key]
            changed = True

    if not changed:
        return 0

    output = "\n".join(f'{key}="{escape(target_values.get(key, ""))}"' for key in TARGET_KEYS) + "\n"
    target_path.write_text(output, encoding="utf-8")
    print(f"Updated {target_path} from {source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
