from __future__ import annotations

import dataclasses
from typing import Optional, Generator

import dacite
import structlog

logger: structlog.stdlib.BoundLogger = structlog.get_logger()


class Base:
    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data, dacite_config)

    def __format__(self, format_spec):
        match format_spec:
            case "klg":
                return self.format()
            case _:
                return super().__format__(format_spec)

    def format_line_generator(self) -> Generator[str, None, None]:
        raise NotImplementedError()

    def format(self):
        return "\n".join(self.format_line_generator())


@dataclasses.dataclass
class GenericEntry(Base):
    type: str  # "range",
    summary: str  # "welcome call",
    tags: list[str]  # [],
    total: str  # "1h",
    total_mins: int  # 60,

    @classmethod
    def transform(cls, value: dict):
        match value.get("type"):
            case "range":
                real_class = Range
            case "open_range":
                real_class = OpenRange
            case "duration":
                real_class = Duration
            case unknown:
                raise ValueError(f"Unknown type: {unknown!r}")
        return real_class.load(value)


@dataclasses.dataclass
class Duration(GenericEntry):
    pass


@dataclasses.dataclass
class Range(GenericEntry):
    start: str  # "12:00",
    start_mins: int  # 720,
    end: str  # "13:00",
    end_mins: int  # 780


@dataclasses.dataclass
class OpenRange(GenericEntry):
    start: str  # "12:00",
    start_mins: int  # 720,


@dataclasses.dataclass
class Record(Base):
    date: str  # "2022-10-10"
    summary: str  # "waiting to start at #X ..."
    total: str  # "0m"
    total_mins: int  # 0
    should_total: str  # "0m!"
    should_total_mins: int  # 0
    diff: str  # "0m"
    diff_mins: int  # 0
    tags: list[str]  # ["#X"]
    entries: list[GenericEntry]

    def format_line_generator(self):
        if self.should_total_mins:
            yield f"{self.date} ({self.should_total})"
        else:
            yield self.date
        if self.summary:
            yield self.summary


@dataclasses.dataclass
class Error(Base):
    line: int
    column: int
    length: int
    title: str
    details: str


@dataclasses.dataclass
class Result(Base):
    records: list[Record]
    errors: Optional[list[Error]]

    def format_line_generator(self) -> Generator[str, None, None]:
        yield from (format(rec, "klg") for rec in self.records)
        yield ""


dacite_config = dacite.Config(strict=True, strict_unions_match=True, type_hooks={
    GenericEntry: GenericEntry.transform,
})
