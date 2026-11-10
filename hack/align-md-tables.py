#!/usr/bin/env python3
"""Align GFM Markdown tables: pad every cell so the pipes line up in a terminal.

Prettier (the repository formatter) normalises tables to a minimal style and does not align
columns, so a table is readable only in a rendered view. This script pads the cells in place and
keeps the alignment hints (`:---`, `:---:`, `---:`) of the delimiter row.

It rewrites only table blocks; every other line is copied byte for byte.

    hack/align-md-tables.py FILE...
    hack/align-md-tables.py --check FILE...
"""

import re
import sys

DELIMITER_CELL = re.compile(r"^:?-+:?$")


def split_row(line):
    """Split a table row on unescaped pipes, dropping the outer pipes."""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|") and not body.endswith(r"\|"):
        body = body[:-1]
    cells = re.split(r"(?<!\\)\|", body)
    return [cell.strip() for cell in cells]


def is_delimiter(line):
    cells = split_row(line)
    return bool(cells) and all(DELIMITER_CELL.match(cell) for cell in cells)


def alignment_of(cell):
    left = cell.startswith(":")
    right = cell.endswith(":")
    if left and right:
        return "center"
    if left:
        return "left"
    if right:
        return "right"
    return None


def render(cells, widths, aligns):
    parts = []
    for cell, width, align in zip(cells, widths, aligns):
        if align == "center":
            padded = cell.center(width)
        elif align == "right":
            padded = cell.rjust(width)
        else:
            padded = cell.ljust(width)
        parts.append(f" {padded} ")
    return "|" + "|".join(parts) + "|"


def align_table(lines):
    """Return the aligned lines, or None when the block does not look like a table."""
    if len(lines) < 2:
        return None
    header = split_row(lines[0])
    delimiter = split_row(lines[1])
    if not header or not delimiter or len(header) != len(delimiter):
        return None
    if not all(DELIMITER_CELL.match(cell) for cell in delimiter):
        return None
    rows = [header]
    for line in lines[2:]:
        cells = split_row(line)
        if len(cells) < len(header):
            cells += [""] * (len(header) - len(cells))
        rows.append(cells[: len(header)])
    aligns = [alignment_of(cell) for cell in delimiter]
    widths = []
    for index in range(len(header)):
        widths.append(max(3, *(len(row[index]) for row in rows)))
    out = [render(rows[0], widths, aligns)]
    out.append(render(["-" * w for w in widths], widths, aligns))
    for row in rows[1:]:
        out.append(render(row, widths, aligns))
    return out


def process(text):
    lines = text.splitlines()
    out = []
    index = 0
    changed = False
    while index < len(lines):
        if (
            "|" in lines[index]
            and index + 1 < len(lines)
            and is_delimiter(lines[index + 1])
        ):
            end = index + 2
            while end < len(lines) and "|" in lines[end] and lines[end].strip():
                end += 1
            aligned = align_table(lines[index:end])
            if aligned is not None:
                out.extend(aligned)
                changed = changed or aligned != lines[index:end]
                index = end
                continue
        out.append(lines[index])
        index += 1
    return "\n".join(out) + ("\n" if text.endswith("\n") else ""), changed


def main(argv):
    check = False
    files = []
    for arg in argv:
        if arg == "--check":
            check = True
        elif arg.startswith("-"):
            sys.exit(f"unknown option: {arg}")
        else:
            files.append(arg)
    if not files:
        sys.exit(__doc__)

    failed = False
    for path in files:
        with open(path) as handle:
            text = handle.read()
        new_text, changed = process(text)
        if changed:
            if check:
                print(f"would reformat {path}")
                failed = True
            else:
                with open(path, "w") as handle:
                    handle.write(new_text)
                print(f"reformatted {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
