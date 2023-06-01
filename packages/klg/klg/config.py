from __future__ import annotations

import dataclasses
from pathlib import Path

import dacite


@dataclasses.dataclass
class TagMapping:
    tag: str
    value: str


@dataclasses.dataclass
class FieldFromTags:
    field: str
    mappings: list[TagMapping]


@dataclasses.dataclass
class ReportConfig:
    resource: str = ""
    name: str = ""
    tags: list[str] = dataclasses.field(default_factory=list)
    fields: list[FieldFromTags] = dataclasses.field(default_factory=dict)

    def map_tags(self, tags: set[str]):
        ret = {}
        for entry in self.fields:
            field_name = entry.field
            mappings = entry.mappings
            if not mappings[-1].tag:
                ret[field_name] = mappings[-1].value
            else:
                ret[field_name] = ""
            for mapping in mappings:
                if mapping.tag in tags:
                    ret[field_name] = mapping.value
                    break
        return ret


@dataclasses.dataclass
class ProfileConfig:
    name: str
    dir: Path
    write_tags: list[str] = dataclasses.field(default_factory=list)
    reports: dict[str, ReportConfig] = dataclasses.field(default_factory=dict)

    def __post_init__(self):
        self.write_tags = self.write_tags or [self.name]


@dataclasses.dataclass
class Config:
    path: Path = None
    selected_profile: str = None
    resolve_symlinks: bool = True
    profiles: dict[str, ProfileConfig] = dataclasses.field(default_factory=dict)

    @classmethod
    def load(cls, data: dict, path: Path, **extra):
        return dacite.from_dict(
            cls, {"path": path, **extra, **data}, config=dacite_config
        )

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
    strict=True, strict_unions_match=True, type_hooks={Path: Path}
)
