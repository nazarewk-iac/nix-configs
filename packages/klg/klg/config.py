from __future__ import annotations

import functools

import dacite
import dataclasses
import enum
import tomllib
from pathlib import Path


class TagsType(enum.StrEnum):
    record = "record"
    entry = "entry"


class ReportType(enum.StrEnum):
    complete = "complete"
    daily = "daily"


@dataclasses.dataclass
class TagMapping:
    value: str
    tags: set[str] = frozenset()
    record_tags: set[str] = frozenset()
    entry_tags: set[str] = frozenset()
    not_tags: set[str] = frozenset()
    not_record_tags: set[str] = frozenset()
    not_entry_tags: set[str] = frozenset()

    @staticmethod
    def _matches(
        *,
        tags: set[str],
        include: set[str],
        exclude: set[str],
    ):
        if include and not include.issubset(tags):
            return False
        if exclude and exclude.issubset(tags):
            return False
        return True

    def matches(
        self,
        type: TagsType | None = None,
        entry_tags: set[str] = frozenset(),
        record_tags: set[str] = frozenset(),
    ):
        if not self._matches(
            include=self.tags,
            exclude=self.not_tags,
            tags=entry_tags | record_tags,
        ):
            return False
        if not self._matches(
            include=self.record_tags,
            exclude=self.not_record_tags,
            tags=record_tags,
        ):
            return False
        if type == TagsType.entry and not self._matches(
            include=self.entry_tags,
            exclude=self.not_entry_tags,
            tags=entry_tags,
        ):
            return False

        return True


@dataclasses.dataclass
class FieldFromTags:
    header: str
    mappings: list[TagMapping]
    default: str = ""
    type: TagsType = TagsType.entry
    multiplier: bool = False

    @staticmethod
    def to_float(value: str, default="0.0"):
        return float(value.strip() or default)

    def get_value(
        self,
        *,
        value,
        type: TagsType,
        record_tags: set[str],
        entry_tags: set[str],
    ):
        default = self.default
        if self.multiplier:
            default = self.to_float(default)

        if type is not None and type != self.type:
            return default

        for mapping in self.mappings:
            if not mapping.matches(
                type=type,
                entry_tags=entry_tags,
                record_tags=record_tags,
            ):
                continue
            default = mapping.value
            if self.multiplier:
                return self.to_float(mapping.value) * value
            return default
        return default


@dataclasses.dataclass
class ReportConfig:
    resource: str = ""
    name: str = ""
    type: ReportType = ReportType.complete
    tags: set[str] = dataclasses.field(default_factory=list)
    fields: list[FieldFromTags] = dataclasses.field(default_factory=dict)

    @functools.cached_property
    def headers(self):
        return list(f.header for f in self.fields)

    @functools.cached_property
    def fields_map(self):
        return {f.header: f for f in self.fields}

    def map_tags(
        self,
        value: float,
        type: TagsType | None = None,
        entry_tags: set[str] = frozenset(),
        record_tags: set[str] = frozenset(),
    ):
        ret = {}
        field: FieldFromTags
        for field in self.fields:
            ret[field.header] = field.get_value(
                value=value,
                type=type,
                record_tags=record_tags,
                entry_tags=entry_tags,
            )
        return ret


@dataclasses.dataclass
class ProfileConfig:
    name: str
    dir: Path
    reports: dict[str, ReportConfig] = dataclasses.field(default_factory=dict)

    def load_child(self, data: dict):
        data.setdefault("name", self.name)
        data.setdefault("dir", self.dir)
        child = dacite.from_dict(ProfileConfig, data, config=dacite_config)
        self.reports.update(child.reports)


@dataclasses.dataclass
class Config:
    path: Path
    selected_profile: str = None
    resolve_symlinks: bool = True
    profiles: dict[str, ProfileConfig] = dataclasses.field(default_factory=dict)

    @classmethod
    def load(cls, data: dict):
        self: Config = dacite.from_dict(cls, data, config=dacite_config)
        for profile in self.profiles.values():
            path = self.mkpath(profile.dir) / "klg.toml"
            if path.exists():
                data = tomllib.loads(path.read_text())
                profile.load_child(data)
        return self

    @property
    def base_dir(self):
        if self.resolve_symlinks:
            return self.path.parent.resolve()
        return self.path.parent

    def get_profile(self, id: str = None):
        return self.profiles[id or self.selected_profile]

    def profile_dir(self, id: str = None):
        profile_dir = self.get_profile(id).dir
        return self.mkpath(profile_dir)

    def profile_paths(self, id: str = None):
        dir = self.profile_dir(id)
        yield dir / "default.klg"

    def mkpath(self, path: str | Path):
        path = Path(path)
        if not path.is_absolute():
            path = self.base_dir / path
        return path.resolve()


def path_hook(*args, **kwargs):
    print(args)
    print(kwargs)
    return


dacite_config = dacite.Config(
    strict=True,
    strict_unions_match=True,
    cast=[
        set,
        Path,
        ReportType,
        TagsType,
    ],
    type_hooks={},
)
