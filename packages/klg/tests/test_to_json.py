import textwrap

import pytest

from klg.json_types import Range, OpenRange, Duration

pytestmark = pytest.mark.anyio


async def test_empty(klog):
    result = await klog.to_json(b"")
    assert not result.records
    assert not result.errors


async def test_invalid(klog):
    result = await klog.to_json(b"11")
    assert not result.records
    assert len(result.errors) == 1


async def test_range_entry_types(klog):
    result = await klog.to_json(textwrap.dedent("""\
    2022-10-10
      08:00 - 10:00 #range
      30m #duration
      -30m #duration #negative
      11:00 - ? #range #open
    """))

    assert len(result.records) == 1
    record = result.records[0]
    entries = record.entries
    assert len(entries) == 4
    assert list(map(type, entries)) == [Range, Duration, Duration, OpenRange]
