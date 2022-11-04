import logging

import structlog


def logging():
    logging.basicConfig(level=logging.INFO)
    structlog.configure(logger_factory=structlog.stdlib.LoggerFactory())
