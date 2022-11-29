from __future__ import annotations

import dataclasses
import textwrap
from abc import ABC
from typing import Optional, Generator

import dacite
import structlog

logger: structlog.stdlib.BoundLogger = structlog.get_logger()

format_name = "klg"


class Base:
    len_shifted_time = len("<23:00")
    len_max = len_shifted_time + len(" - ") + len_shifted_time
    indent_summary = " " * (len_max + 1)
    indent_entry = "  "

    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data, dacite_config)

    def __format__(self, format_spec):
        match format_spec:
            case "klg" | "k":
                return self.format()
            case _:
                return super().__format__(format_spec)

    def format_line_generator(self) -> Generator[str, None, None]:
        raise NotImplementedError()

    def format(self):
        return "\n".join(self.format_line_generator())

    @staticmethod
    def format_time(mins: int):
        pieces = []
        hours = mins // 60
        minutes = mins % 60

        day_shift_backward = mins < 0
        day_shift_forward = mins > 1440

        if day_shift_backward:
            pieces.append("<")
            hours += 24
            minutes = -minutes
        elif day_shift_forward:
            hours -= 24

        pieces.append(f"{hours:02d}:{minutes % 60:02d}")

        if day_shift_forward:
            pieces.append(">")
        return "".join(map(str, pieces))

    @staticmethod
    def format_duration(mins: int):
        pieces = []
        if mins < 0:
            pieces.append("-")
            mins = -mins
        if hours := mins // 60:
            pieces.append(f"{hours}h")
        if minutes := mins % 60:
            pieces.append(f"{minutes}m")
        return "".join(pieces)


@dataclasses.dataclass
class EntryBase(Base, ABC):
    summary: str  # "welcome call",
    tags: list[str]  # ["#X"]

    def format_summary(self, prefix: str = None):
        if prefix is None:
            prefix = self.indent_summary

        def gen():
            for idx, line in enumerate(self.summary.splitlines(False)):
                stripped = line.strip()
                if idx == 0:
                    yield stripped
                    continue
                yield f"{prefix}{stripped}"

        return "\n".join(gen())


@dataclasses.dataclass
class GenericEntry(EntryBase):
    type: str  # "range",
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
    def format_line_generator(self):
        value = self.format_duration(self.total_mins)
        yield f"{value:<{self.len_max}s} {self.format_summary()}"


@dataclasses.dataclass
class Range(GenericEntry):
    start: str  # "12:00",
    start_mins: int  # 720,
    end: str  # "13:00",
    end_mins: int  # 780

    def format_line_generator(self):
        start = f"{self.format_time(self.start_mins):<{self.len_shifted_time}s}"
        end = f"{self.format_time(self.end_mins):<{self.len_shifted_time}s}"
        value = f"{start} - {end}"
        yield f"{value} {self.format_summary()}"


@dataclasses.dataclass
class OpenRange(GenericEntry):
    start: str  # "12:00",
    start_mins: int  # 720,

    def format_line_generator(self):
        value = f"{self.format_time(self.start_mins):<{self.len_shifted_time}s} - {'?':<{self.len_shifted_time}s}"
        yield f"{value} {self.format_summary()}"


@dataclasses.dataclass
class Record(EntryBase):
    date: str  # "2022-10-10"
    total: str  # "0m"
    total_mins: int  # 0
    should_total: str  # "0m!"
    should_total_mins: int  # 0
    diff: str  # "0m"
    diff_mins: int  # 0
    entries: list[GenericEntry]

    def format_line_generator(self):
        if self.should_total_mins:
            yield f"{self.date} ({self.format_duration(self.should_total_mins)}!)"
        else:
            yield self.date
        if self.summary:
            yield self.format_summary("")
        for entry in self.entries:
            yield textwrap.indent(format(entry, format_name), self.indent_entry)
        yield ""


@dataclasses.dataclass
class GenericError(Base, Exception):
    line: int
    column: int
    length: int
    title: str
    details: str
    lines: list[str] = dataclasses.field(default_factory=list)

    def __str__(self):
        return self.format()

    def format_line_generator(self, context: int = 2) -> Generator[str, None, None]:
        yield self.title
        yield f"line={self.line!r} column={self.column!r} length={self.length!r}"
        yield self.details
        number_width = len(str(len(self.lines)))

        line_idx = self.line - 1
        column_idx = self.column - 1

        start = max(line_idx - context, 0)
        end = min(line_idx + context, len(self.lines))
        for num, line in enumerate(self.lines[start: end], start=start):
            yield f"{num:0{number_width}d}:" + line
            if num == line_idx:
                yield " " * number_width + ":" + " " * column_idx + "^" * self.length

    @classmethod
    def transform(cls, value: dict):
        # see https://github.com/jotaen/klog/blob/7996ca8c5687fbb231cb5883b52d585bba3b9a2b/klog/parser/error.go
        match value.get("title"):
            case "Invalid date":
                real_class = InvalidDateError
            case "Unexpected indentation":
                real_class = UnexpectedIndentationError
            case _:
                real_class = cls
        return real_class.load(value)


@dataclasses.dataclass
class InvalidDateError(GenericError):
    pass


@dataclasses.dataclass
class UnexpectedIndentationError(GenericError):
    pass


class KlogErrorGroup(ExceptionGroup):
    exceptions: tuple[GenericError]


@dataclasses.dataclass
class Result(Base):
    lines: list[str]
    records: Optional[list[Record]]
    errors: Optional[list[GenericError]]

    def format_line_generator(self):
        yield from (format(rec, format_name) for rec in self.records)

    def raise_errors(self):
        if not self.errors:
            return
        raise KlogErrorGroup("Error parsing klog text", self.errors)


dacite_config = dacite.Config(strict=True, strict_unions_match=True, type_hooks={
    GenericEntry: GenericEntry.transform,
    GenericError: GenericError.transform,
})
