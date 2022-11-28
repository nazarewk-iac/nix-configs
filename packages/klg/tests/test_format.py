import textwrap

import pytest

from klg.json_types import Range, OpenRange, Duration

pytestmark = pytest.mark.anyio


def cleanup(text):
    text = text.removeprefix("\n")
    ret = textwrap.dedent(text)
    return ret


@pytest.mark.parametrize("text", [
    "2022-10-10\n",
    "2022-10-10 (1h!)\n",
    """
        2022-10-10
        some summary
    """,
    """
        2022-10-10
        some summary
        another line
    """,
])
async def test_unmodified(text, klog):
    cleaned_up = cleanup(text)
    assert format(await klog.to_json(cleaned_up), "klg") == cleaned_up
