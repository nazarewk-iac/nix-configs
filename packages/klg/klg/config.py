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

    def __post_init__(self):
        self.write_tags = self.write_tags or [self.name]


@dataclasses.dataclass
class Config:
    profiles: dict[str, ProfileConfig] = dataclasses.field(default_factory=dict)
    reports: dict[str, ReportConfig] = dataclasses.field(default_factory=dict)

    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data)


dacite_config = dacite.Config(strict=True, strict_unions_match=True, type_hooks={})
