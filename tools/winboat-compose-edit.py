#!/usr/bin/env python3
"""Conservatively inspect or edit WinBoat's QEMU ARGUMENTS scalar."""
from __future__ import annotations

import re
import sys
from pathlib import Path

IRIS_ARG = "-device usb-host,vendorid=0x0a38,productid=0x0161"
IRIS_RE = re.compile(
    r"(?:^|\s)-device\s+usb-host\s*,\s*vendorid=0x0*a38\s*,\s*productid=0x0*161(?:\s*,\s*[^\s,]+=[^\s,]+)*(?=\s|$)",
    re.IGNORECASE,
)
MAP_RE = re.compile(r"^(?P<prefix>\s*ARGUMENTS\s*:\s*)(?P<value>.*?)(?P<nl>\r?\n?)$")
LIST_RE = re.compile(r"^(?P<prefix>\s*-\s*ARGUMENTS=)(?P<value>.*?)(?P<nl>\r?\n?)$")


def split_scalar(raw: str) -> tuple[str, str, str]:
    """Return decoded-ish content plus opening/closing quote markers."""
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        return raw[1:-1], '"', '"'
    if len(raw) >= 2 and raw[0] == raw[-1] == "'":
        return raw[1:-1], "'", "'"
    if " #" in raw:
        value, comment = raw.split(" #", 1)
        return value.rstrip(), "", " #" + comment
    return raw.rstrip(), "", ""


def join_scalar(value: str, opening: str, closing: str) -> str:
    return opening + value + closing


def transform(text: str, action: str) -> tuple[str, bool, bool]:
    lines = text.splitlines(keepends=True)
    matches: list[tuple[int, re.Match[str]]] = []
    for idx, line in enumerate(lines):
        match = MAP_RE.match(line) or LIST_RE.match(line)
        if match:
            matches.append((idx, match))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one WinBoat ARGUMENTS entry; found {len(matches)}")
    idx, match = matches[0]
    value, opening, closing = split_scalar(match.group("value"))
    count = len(IRIS_RE.findall(value))
    present = count > 0
    if action == "inspect":
        return text, present, False
    if action == "add":
        if count > 1:
            raise SystemExit(f"refusing ambiguous duplicate IRIS arguments: {count}")
        new_value = value if present else f"{value.rstrip()} {IRIS_ARG}".strip()
    elif action == "remove":
        new_value = IRIS_RE.sub("", value)
        new_value = re.sub(r"[ \t]+", " ", new_value).strip()
    else:
        raise SystemExit(f"unsupported action: {action}")
    changed = new_value != value
    lines[idx] = (
        match.group("prefix") + join_scalar(new_value, opening, closing) + match.group("nl")
    )
    return "".join(lines), present, changed


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"inspect", "add", "remove"}:
        print(f"usage: {sys.argv[0]} inspect|add|remove COMPOSE", file=sys.stderr)
        return 2
    path = Path(sys.argv[2])
    text = path.read_text(encoding="utf-8")
    result, present, changed = transform(text, sys.argv[1])
    if sys.argv[1] == "inspect":
        value_match = next(
            (MAP_RE.match(line) or LIST_RE.match(line) for line in text.splitlines(keepends=True)
             if MAP_RE.match(line) or LIST_RE.match(line)),
            None,
        )
        assert value_match is not None
        raw_value, _, _ = split_scalar(value_match.group("value"))
        count = len(IRIS_RE.findall(raw_value))
        print(f"IRIS_ARGUMENT={'PRESENT' if present else 'ABSENT'}")
        print(f"IRIS_ARGUMENT_COUNT={count}")
        print("ARGUMENTS_ENTRY=VALID")
    else:
        sys.stdout.write(result)
        print(f"winboat-compose-edit: changed={'yes' if changed else 'no'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
