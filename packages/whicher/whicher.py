#!/usr/bin/env python
import argparse
import dataclasses
import functools
import json
import os
import shlex
from pathlib import Path
from typing import Callable, Generator

import sys


class ActionExtendConst(argparse.Action):
    def __init__(self, **kwargs):
        super().__init__(nargs=0, **kwargs)

    def __call__(self, parser, namespace, values, option_string=None):
        items = getattr(namespace, self.dest, None) or []
        items.extend(self.const)
        setattr(namespace, self.dest, items)


@dataclasses.dataclass
class SourceSpec:
    spec: str

    def __post_init__(self):
        self.paths = [Path(value) / self.sub_path for value in self.env_entries]

    def __str__(self):
        return self.spec

    @functools.cached_property
    def env_entries(self):
        name: str
        *_, name = self.spec.rsplit("@", maxsplit=1)
        if os.path.pathsep in name or os.path.sep in name:
            value = name
        else:
            value = os.environ.get(name, "")
        return [entry for entry in value.split(os.path.pathsep) if entry]

    @functools.cached_property
    def sub_path(self):
        if "@" in self.spec:
            sub_path, *_ = self.spec.rsplit("@", maxsplit=1)
            return Path(sub_path)
        return Path(".")


@dataclasses.dataclass
class ResultSource:
    spec: str
    entry: Path


@dataclasses.dataclass
class Result:
    match: Path
    resolved: Path = dataclasses.field(init=False)
    source: ResultSource

    def __post_init__(self):
        self.resolved = self.match.resolve()

    def __str__(self):
        return self.__format__("auto")

    def __format__(self, format_spec):
        match format_spec:
            case "j" | "json":
                return json.dumps(dataclasses.asdict(self), default=str)
            case "a" | "auto":
                if self.match == self.resolved:
                    return str(self.resolved)
                return f"{self.match} -> {self.resolved}"
            case "b" | "both":
                return f"{self.match} -> {self.resolved}"
            case "m" | "match":
                return str(self.match)
            case "r" | "resolved":
                return str(self.resolved)
            case _:
                raise ValueError(f"Unknown formatter: {format_spec}")


@dataclasses.dataclass
class Program:
    sources: list[SourceSpec]
    recursive: bool
    unique: bool
    output: str
    limit: int
    patterns: list[str]

    def __post_init__(self):
        self.sources = list(map(SourceSpec, self.sources))

    def iter_matches(self) -> Generator[Result, None, None]:
        def iter_pattern(pattern: str):
            for source in self.sources:
                for entry in source.paths:
                    glob = entry.rglob if self.recursive else entry.glob
                    for match in glob(pattern):
                        yield Result(
                            source=ResultSource(
                                spec=source.spec,
                                entry=entry,
                            ),
                            match=match,
                        )

        for pattern in self.patterns:
            found = False
            for match in iter_pattern(pattern):
                found = True
                yield match
            if not found:
                sources = " ".join(map(str, self.sources))
                print(f"{pattern} was not found in {sources}", file=sys.stderr)

    @functools.cached_property
    def results(self) -> list[Result]:
        ret = []
        occurrences = set()
        for result in self.iter_matches():
            if 0 <= self.limit <= len(ret):
                break
            if self.unique:
                if result.resolved in occurrences:
                    continue
                occurrences.add(result.resolved)
            ret.append(result)
        return ret

    @classmethod
    def create(cls, args: list[str]):
        source_examples = [
            "applications@XDG_DATA_DIRS",
            "XDG_DATA_DIRS",
            "PATH",
        ]
        source_examples.extend(map(shlex.quote, source_examples[:]))
        source_examples = list({e: None for e in source_examples})

        parser = argparse.ArgumentParser(
            description="A script that helps you find files in $PATH-style variables",
        )
        parser.add_argument(
            "patterns",
            metavar="GLOB",
            nargs="+",
            help="filename glob patterns to search for",
        )
        parser.add_argument(
            "-s",
            "--source",
            dest="sources",
            help=f"Where to look for patterns? examples: {', '.join(source_examples)}",
        )
        parser.add_argument(
            "--xdg",
            action=ActionExtendConst,
            const=[
                "applications@XDG_DATA_HOME",
                "applications@XDG_DATA_DIRS",
            ],
            dest="sources",
            help="XDG application definitions",
        )
        parser.add_argument(
            "--kde",
            action=ActionExtendConst,
            const=[
                "XDG_CONFIG_HOME",
                "XDG_CONFIG_DIRS",
            ],
            dest="sources",
            help="search for KDE config files",
        )
        parser.add_argument(
            "-R",
            "--recursive",
            action="store_true",
            help="search for patterns recursively",
        )
        parser.add_argument(
            "-l",
            "--limit",
            metavar="NUM",
            type=int,
            default=1,
            help="limit number of results (-1 for all)",
        )
        parser.add_argument(
            "-u",
            "--unique",
            action="store_true",
            help="do not return same (resolved)  file more than once",
        )
        parser.add_argument(
            "-o",
            "--output",
            choices=[
                "j",
                "json",
                "a",
                "auto",
                "b",
                "both",
                "m",
                "match",
                "r",
                "resolved",
            ],
            default="match",
            help="output formatting",
        )

        args = parser.parse_args(args=args)
        return cls(**args.__dict__)

    def run(self):
        for result in self.results:
            print(f"{result:{self.output}}")


def main():
    Program.create(sys.argv[1:]).run()


if __name__ == "__main__":
    main()
