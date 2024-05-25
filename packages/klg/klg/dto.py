from __future__ import annotations

import datetime

import dataclasses
import difflib
import functools
import re
import textwrap
from abc import ABC
from collections import defaultdict
from typing import Generator, Optional

import dacite
import pendulum
import structlog

logger: structlog.stdlib.BoundLogger = structlog.get_logger()

format_name = "klg"


class Tag(str):
    """
    Tag in formats:
    - #tagName
    - #tagName=simple-value
    - #tagName="with spaces double-quoted"
    - #tagName='with spaces single-quoted'
    """

    pattern = re.compile(
        r"""#(?P<key>[^= ]+)(=(?P<value>('[^']*')|("[^"]*")|([^"' ]*)))?""",
    )

    def __repr__(self):
        cls = self.__class__
        return f"{cls.__name__}({repr(self.normalized)})"

    def __format__(self, format_spec):
        return self.normalized

    def __hash__(self):
        """
        >>> hash(Tag('#Key')) == hash('#key')
        True
        """
        return hash(self.normalized)

    def __eq__(self, other):
        """
        >>> Tag('#UPPERCASE') == '#UPPERCASE'
        True
        >>> Tag('#UPPERCASE=UPPERCASE') == '#UPPERCASE=UPPERCASE'
        True
        >>> Tag('#UPPERCASE=UPPERCASE') == '#UPPERCASE=uppercase'
        False
        >>> Tag('#key=123') == '#key=123'
        True
        >>> Tag('#key="\\'"') == '#key="\\'"'
        True
        """
        if not isinstance(other, self.__class__):
            other = self.__class__(other)
        return self.normalized == other.normalized

    @classmethod
    def parse_many(cls, text: str):
        return list(cls.pattern.finditer(text))

    @classmethod
    def parse_single(cls, text: str):
        return cls.pattern.fullmatch(text)

    @functools.cached_property
    def match(self):
        match = self.parse_single(self)
        assert match
        return match

    @functools.cached_property
    def key(self):
        return self.match.group("key")

    @functools.cached_property
    def value(self):
        value = self.match.group("value") or ""
        for c in ("'", '"'):
            if value.startswith(c) and value.endswith(c):
                value = value[1:-1]
        return value

    @functools.cached_property
    def quoted_value(self):
        if value := self.value:
            if " " in value:
                if '"' in value:
                    value = f"'{value}'"
                else:
                    value = f'"{value}"'
        return value

    @functools.cached_property
    def normalized(self):
        pieces = [f"#{self.key.lower()}"]
        if value := self.value:
            if " " in value:
                if '"' in value:
                    value = f"'{value}'"
                else:
                    value = f'"{value}"'
            pieces.append(f"={value}")
        return "".join(pieces)


class Base:
    len_shifted_time = len("<23:00")
    len_max = len_shifted_time + len(" - ") + len_shifted_time
    indent_summary = " " * (len_max + 1)
    indent_entry = "  "

    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data, config=dacite_config)

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
    tags: set[str]  # ["#X"]

    def __post_init__(self):
        self.summary = self.summary.lstrip()

    def format_summary(self, prefix: str = None):
        if prefix is None:
            prefix = self.indent_summary

        def gen():
            for idx, line in enumerate(self.summary.splitlines(False)):
                stripped = line.strip()
                if not stripped:
                    continue
                if idx == 0:
                    yield stripped
                    continue
                yield f"{prefix}{stripped}"

        return "\n".join(gen())

    def add_tags(self, *tags: str):
        self.tags = set(self.tags) | set(tags)
        missing = [tag for tag in self.tags if tag not in self.summary]
        if missing:
            self.summary = f"{self.summary} {' '.join(missing)}"

    @staticmethod
    def is_same_tag(tag1: str, tag2: str):
        k1, *v1 = tag1.split("=", 1)
        k2, *v2 = tag2.split("=", 1)
        if k1 != k2:
            return False
        if v1 and v2:
            return v1 == v2
        return True

    def has_tag(self, *tags: str):
        for present in self.tags:
            for checked in tags:
                if self.is_same_tag(present, checked):
                    return True
        return False


@dataclasses.dataclass
class GenericEntry(EntryBase):
    type: str  # "range",
    total: str  # "1h",
    total_mins: int  # 60,

    @property
    def current_minutes(self):
        return self.total_mins

    @property
    def current_hours(self):
        return self.current_minutes / 60.0

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

    @property
    def current_minutes(self):
        now = datetime.datetime.now()
        return (60 * now.hour + now.minute) - self.start_mins

    def format_line_generator(self):
        value = f"{self.format_time(self.start_mins):<{self.len_shifted_time}s} - {'?':<{self.len_shifted_time}s}"
        yield f"{value} {self.format_summary()}"


@dataclasses.dataclass
class Record(EntryBase):
    # a record representing day
    date: str  # "2022-10-10"
    total: str = ""  # "0m"
    total_mins: int = 0  # 0
    should_total: str = ""  # "0m!"
    should_total_mins: int = 0  # 0
    diff: str = ""  # "0m"
    diff_mins: int = 0  # 0
    entries: list[GenericEntry] = dataclasses.field(default_factory=list)

    def __post_init__(self):
        self.set_total(self.total_mins, diff=False)
        self.set_should_total(self.should_total_mins, diff=False)
        self.calculate_diff()

    @functools.cached_property
    def date_obj(self) -> pendulum.Date:
        return pendulum.parse(self.date).date()

    def make_totals(self):
        self.total = self.format_duration(self.total_mins)

    def calculate_diff(self):
        self.diff_mins = self.should_total_mins - self.total_mins
        self.diff = self.format_duration(self.diff_mins)

    def set_total(self, mins: int, *, diff=True):
        self.total_mins = mins
        self.total = self.format_duration(self.total_mins)
        if diff:
            self.calculate_diff()

    def set_should_total(self, expected_mins: int = None, *, force=True, diff=True):
        if expected_mins is None:
            expected_mins = self.should_total_mins
        if not force:
            expected_mins = max(expected_mins, self.total_mins)
        self.should_total_mins = expected_mins
        if self.should_total_mins:
            self.should_total = f"{self.format_duration(self.should_total_mins)}!"
        else:
            self.should_total = ""
        if diff:
            self.calculate_diff()

    def format_line_generator(self):
        if self.should_total_mins:
            yield f"{self.date} ({self.format_duration(self.should_total_mins)}!)"
        else:
            yield self.date
        if self.summary:
            yield self.format_summary("")
        for entry in self.entries:
            value = format(entry, format_name)
            yield textwrap.indent(value, self.indent_entry)
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
        for num, line in enumerate(self.lines[start:end], start=start):
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
    records: Optional[list[Record]]
    errors: Optional[list[GenericError]]
    lines: list[str]

    def diff(self, new: list[str] | str = None):
        old = list(f"{line}\n" for line in self.lines)
        if new is None:
            new = list(f"{line}\n" for line in self.format_line_generator())
        if isinstance(new, str):
            new = new.splitlines(keepends=True)
            new.append("\n")
        diff = "".join(difflib.context_diff(old, new))
        return diff

    def format_line_generator(self):
        yield from (format(rec, format_name) for rec in self.records)

    def raise_errors(self):
        if not self.errors:
            return
        raise KlogErrorGroup("Error parsing klog text", self.errors)

    def plan_month(
        self,
        monthly_hours: int = None,
        daily_hours: int = 8,
        now: pendulum.DateTime = None,
        period: pendulum.DateTime = None,
        day_off_tags: set = frozenset(["#off"]),
        not_day_off_tags: set = frozenset(["#nooff"]),
        day_skip_tags: set = frozenset(["#noplan"]),
        entry_skip_tags: set = frozenset(),
        weekend_tag="#off=weekend",
    ):
        result = self

        now = now or pendulum.now()
        now_date = now.date()
        period = (period or now).replace(day=1)
        period_date = period.date()

        date: pendulum.Date
        by_date: dict[pendulum.Date, list[Record]] = defaultdict(list)
        for record in result.records:
            date = record.date_obj
            if (date.year, date.month) == (period_date.year, period_date.month):
                by_date[date].append(record)

        to_plan_mins = 0
        modifiable_records: dict[pendulum.Date, list[Record]] = defaultdict(list)
        workdays = set()
        offdays = set()
        for i in range(1, period.days_in_month + 1):
            date = period_date.replace(day=i)
            records = by_date[date]
            if not records:
                record = Record(date=str(date), summary="", tags=set())
                result.records.append(record)
                records.append(record)
            for record in records:
                is_skipped = record.has_tag(*day_skip_tags)
                is_past = date < now_date
                can_modify = not is_past and not is_skipped

                total_mins = sum(entry.total_mins for entry in record.entries)
                skipped_mins = sum(
                    entry.total_mins
                    for entry in record.entries
                    if entry.has_tag(*entry_skip_tags)
                )
                total_mins -= skipped_mins

                # mark weekends
                if can_modify and date.isoweekday() > 5:
                    record.add_tags(weekend_tag)

                has_off_tag = record.has_tag(weekend_tag, *day_off_tags)
                has_not_off_tag = record.has_tag(*not_day_off_tags)
                is_off = has_off_tag and not has_not_off_tag
                if is_off:
                    offdays.add(record.date_obj)
                else:
                    workdays.add(record.date_obj)
                if can_modify and is_off:
                    record.set_should_total(0)

                # TODO: subtract open-ended range?
                if total_mins > record.should_total_mins or (
                    is_past and total_mins != record.should_total_mins
                ):
                    record.set_should_total(total_mins)

                diff_mins = record.should_total_mins - total_mins
                if date == now_date and diff_mins == 0:
                    to_plan_mins -= record.should_total_mins
                elif is_past or is_skipped:
                    to_plan_mins -= record.should_total_mins
                elif can_modify and not is_off:
                    modifiable_records[record.date_obj].append(record)

        if monthly_hours is not None:
            to_plan_mins += monthly_hours * 60
        else:
            to_plan_mins += len(workdays) * daily_hours * 60

        if not modifiable_records:
            return

        leftover_mins = to_plan_mins % len(modifiable_records)
        expected_daily = int(to_plan_mins / len(modifiable_records))

        for i, records in enumerate(modifiable_records.values()):
            record = records[-1]
            expected = expected_daily
            if i < leftover_mins:
                expected += 1
            record.set_should_total(expected)


dacite_config = dacite.Config(
    strict=True,
    strict_unions_match=True,
    cast=[
        set,
    ],
    type_hooks={
        GenericEntry: GenericEntry.transform,
        GenericError: GenericError.transform,
    },
)
