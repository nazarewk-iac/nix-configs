from __future__ import annotations

import dacite
import dataclasses
import enum
import tomllib
from pathlib import Path


@dataclasses.dataclass
class TagMapping:
    tags: set[str]
    value: str
    strict: bool = False
    record: bool = True
    entry: bool = True

    def matches(
        self,
        type: TagsType,
        entry_tags: set[str] = frozenset(),
        record_tags: set[str] = frozenset(),
    ):
        ret = False
        if not self.strict or type == TagsType.entry:
            ret |= self.entry and self.tags.issubset(entry_tags)
        if not self.strict or type == TagsType.record:
            ret |= self.record and self.tags.issubset(record_tags)
        return ret


@dataclasses.dataclass
class FieldFromTags:
    header: str
    mappings: list[TagMapping]
    multiplier: bool = False


class TagsType(enum.StrEnum):
    none = ""
    record = "record"
    entry = "entry"


class ReportType(enum.StrEnum):
    complete = "complete"
    daily = "daily"


@dataclasses.dataclass
class ReportConfig:
    resource: str = ""
    name: str = ""
    type: ReportType = ReportType.complete
    tags: set[str] = dataclasses.field(default_factory=list)
    fields: list[FieldFromTags] = dataclasses.field(default_factory=dict)

    def map_tags(
        self,
        value: float,
        type: TagsType = TagsType.none,
        entry_tags: set[str] = frozenset(),
        record_tags: set[str] = frozenset(),
    ):
        ret = {}
        for field in self.fields:
            field_name = field.header
            mappings = field.mappings
            if field.multiplier:
                ret[field_name] = 0.0
            else:
                ret[field_name] = ""

            for mapping in mappings:
                if mapping.matches(
                    type=type, entry_tags=entry_tags, record_tags=record_tags
                ):
                    if field.multiplier:
                        ret[field_name] = float(mapping.value) * value
                    else:
                        ret[field_name] = mapping.value
                    break
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
    ],
    type_hooks={},
)
