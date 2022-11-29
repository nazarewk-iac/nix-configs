import pytest

from klg import dto
from . import common

pytestmark = pytest.mark.anyio


async def test_empty(klog):
    result = await klog.to_json(b"")
    assert not result.records
    assert not result.errors


async def test_invalid(klog):
    with pytest.raises(dto.KlogErrorGroup) as exc_info:
        await klog.to_json(b"11")
    group = exc_info.value
    exc = group.exceptions[0]
    assert isinstance(exc, dto.InvalidDateError)


async def test_entry_types(klog):
    result = await klog.to_json(common.cleanup("""
    2022-10-10
      08:00 - 10:00 #range
      30m #duration
      -30m #duration #negative
      11:00 - ? #range #open
      <23:00 - 01:00 #range #day-shift-backwards
      23:00 - 01:00> #range #day-shift-forwards

    2022-10-11
      <23:00 - 01:00> #range #day-shift-both
    """))

    assert len(result.records) == 2

    record, nxt = result.records
    entries = record.entries
    assert len(entries) == 6
    assert list(map(type, entries)) == [dto.Range, dto.Duration, dto.Duration, dto.OpenRange, dto.Range, dto.Range]
    range, duration, negative_duration, open_range, day_shift_backward, day_shift_forward = entries
    assert negative_duration.total_mins == -30

    assert range.start == "8:00"  # it's normalized by klog

    assert open_range.start == "11:00"
    assert open_range.total_mins == 0
    assert day_shift_backward.start_mins == -60
    assert day_shift_forward.end_mins == (1440 + 60)

    assert len(nxt.entries) == 1
    day_shift_both = nxt.entries[0]
    assert day_shift_both.start_mins == -60
    assert day_shift_forward.end_mins == (1440 + 60)


async def test_multiline_content(klog):
    result = await klog.to_json(common.cleanup("""
        2022-10-10
          30m  #indent=1
            #indent=0
             #indent=1
              #indent=2
          30m #indent=0
              #indent=2
      
        2022-10-11
        2-space indent
          30m #indent=0
                #indent=4
      
        2022-10-12
        4-space indent
            30m #indent=0
                #indent=0
      
        2022-10-13
        4-space indent + further indent
            30m #indent=0
                  #indent=2
      
        2022-10-13
        tab indent
        \t30m #indent=0
        \t\t #indent=1
        \t\t\t#indent=1
    """))

    for record in result.records:
        for entry in record.entries:
            found_indents = [line.index("#") for line in entry.summary.splitlines(False)]
            expected_indents = [
                int(line.split("#", 1)[1].split("=", 1)[1])
                for line in entry.summary.splitlines(False)
            ]
            assert found_indents == expected_indents


async def test_multiline_indentation_errors(klog):
    with pytest.raises(dto.KlogErrorGroup) as exc_info:
        await klog.to_json(common.cleanup("""
        2022-10-10
        4-space indent, but less than 4 space on entry summary
            30m #indent=0
              #indent=2
        """))
    group = exc_info.value
    exc = group.exceptions[0]
    assert isinstance(exc, dto.UnexpectedIndentationError)
