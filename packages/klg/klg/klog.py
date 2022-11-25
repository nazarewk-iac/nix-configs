import dataclasses
import json
import shutil
import subprocess
from pathlib import Path

import dacite
import itertools
import structlog

logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@dataclasses.dataclass
class Entry:
    type: str  # "range",
    summary: str  # "welcome call",
    tags: list[str]  # [],
    total: str  # "1h",
    total_mins: int  # 60,

    @classmethod
    def load(cls, data):
        types = dict(
            range=RangeEntry,
        )
        entry_type = types.get(data.get("type"), cls)
        return entry_type(**data)


@dataclasses.dataclass
class RangeEntry(Entry):
    start: str  # "12:00",
    start_mins: int  # 720,
    end: str  # "13:00",
    end_mins: int  # 780


@dataclasses.dataclass
class Record:
    date: str  # "2022-10-10"
    summary: str  # "waiting to start at #X ..."
    total: str  # "0m"
    total_mins: int  # 0
    should_total: str  # "0m!"
    should_total_mins: int  # 0
    diff: str  # "0m"
    diff_mins: int  # 0
    tags: list[str]  # ["#X"]
    entries: list[Entry]

    @classmethod
    def load(cls, data):
        return cls(
            entries=list(map(Entry.load, data.pop("entries") or [])),
            **data,
        )


@dataclasses.dataclass
class Result:
    records: list[Record]
    errors: list | None

    @classmethod
    def load(cls, data):
        return Result(
            records=list(map(Record.load, data.get("records") or [])),
            errors=data.get("errors")
        )


@dataclasses.dataclass
class Klog:
    binary: Path = dataclasses.field(default_factory=lambda: Path(shutil.which("klog")))

    def cmd(self, args, **kwargs):
        kwargs.setdefault("stdout", subprocess.PIPE)
        kwargs.setdefault("check", True)
        arguments = list(map(str, itertools.chain([self.binary], args)))
        logger.debug("running command", argv=arguments)
        return subprocess.run(
            arguments,
            **kwargs,
        )

    def read(self, *paths: Path | str):
        paths = paths or ["@default"]
        proc = self.cmd(["json", *paths])
        raw = json.loads(proc.stdout)
        return Result.load(raw)
