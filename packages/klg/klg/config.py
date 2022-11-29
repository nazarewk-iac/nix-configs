from __future__ import annotations

import dataclasses

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
class Config:
    reports: dict[str, ReportConfig] = dataclasses.field(default_factory=dict)

    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data)
