import textwrap

import pytest

from klg.klog import Klog


@pytest.fixture(scope="session")
def klog():
    return Klog()


def cleanup(text):
    text = text.removeprefix("\n")
    ret = textwrap.dedent(text)
    return ret
