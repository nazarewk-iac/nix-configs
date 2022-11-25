import logging as _logging

import structlog


def logging():
    _logging.basicConfig(level=_logging.INFO)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())
