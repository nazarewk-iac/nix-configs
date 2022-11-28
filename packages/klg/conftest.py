import pytest

from klg.klog import Klog


@pytest.fixture(scope="session")
def klog():
    return Klog()
