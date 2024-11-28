#!/usr/bin/env python
"""
kdn-anonymize SEARCH_DIR [SEARCH_DIR...]

    Anonymizes STDIN based on the content of regex `pattern` files
     replacing those with `replacement` siblings.

    Starts by searching recursively for `pattern` & `replacement` file pairs.
"""

import dataclasses
import functools
import os
import re
import sys
from pathlib import Path


@dataclasses.dataclass
class Replacement:
    pattern: str
    replacement: str
    dirname: str

    def __post_init__(self):
        self.re = re.compile(self.pattern)

    def replace_count(self, txt):
        return self.re.subn(self.replacement or self.dirname, txt)

    @functools.cached_property
    def final_replacement(self):
        if self.replacement:
            return self.replacement
        return f"<<{self.dirname!r}>>"

    @staticmethod
    def is_match(dir: Path):
        pattern = (dir / "pattern").resolve()
        return pattern.is_file()

    @classmethod
    def try_create(cls, dir: Path):
        if cls.is_match(dir):
            try:
                replacement = (dir / "replacement").read_text()
            except FileNotFoundError:
                replacement = ""
            return cls(
                dirname=dir.name,
                pattern=(dir / "pattern").read_text(),
                replacement=replacement,
            )
        return None

    @classmethod
    def iter(cls, search_dirs: list[Path]):
        expected = {"pattern"}
        for search_dir in search_dirs:
            for root, dirs, files in search_dir.walk(top_down=False):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                if expected.issubset(files) and (repl := cls.try_create(root)):
                    yield repl


def get_defaults():
    return [
        stripped
        for entry in os.environ.get("KDN_ANONYMIZE_DEFAULTS", "").split("\n")
        if (stripped := entry.strip())
    ]


def log(*args, **kwargs):
    kwargs.setdefault("file", sys.stderr)
    print(*args, **kwargs)


def main(_, *args):
    args = args or get_defaults()
    directories = list(map(Path, args))
    replacements = list(Replacement.iter(directories))

    replacement_count = 0
    line_count = 0
    for line in sys.stdin:
        for r in replacements:
            line, count = r.replace_count(line)
            replacement_count += count
        sys.stdout.write(line)
        line_count += 1

    log(f"replaced {replacement_count} matches over {line_count} lines")


if __name__ == "__main__":
    main(*sys.argv)
