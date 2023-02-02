import textwrap

import pytest

from . import common

pytestmark = pytest.mark.anyio


@pytest.mark.parametrize(
    "text",
    map(
        common.cleanup,
        [
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
            """
        2022-10-10
          08:00  - 09:00  #test
    """,
            common.complete_formatted,
        ],
    ),
)
async def test_unmodified(text, klog):
    assert format(await klog.to_json(text), "klg") == text


@pytest.mark.parametrize(
    "text,result",
    [
        list(map(common.cleanup, args))
        for args in [[common.complete_unformatted, common.complete_formatted]]
    ],
)
async def test_modified(text, result, klog):
    assert format(await klog.to_json(text), "klg") == result
