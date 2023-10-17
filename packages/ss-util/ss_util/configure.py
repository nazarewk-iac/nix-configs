import logging as _logging

import structlog


def logging(**kwargs):
    _logging.basicConfig(level=_logging.INFO, **kwargs)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())
