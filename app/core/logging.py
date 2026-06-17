"""
Centralised logging configuration.

Usage::

    from app.core.logging import get_logger

    logger = get_logger(__name__)
    logger.info("Processing request", extra={"store_id": "abc"})

In production (APP_ENV=="production") logs are emitted as JSON.
In all other environments a human-readable format is used instead.
"""

import json
import logging
import sys

from app.core.config import settings


class _JsonFormatter(logging.Formatter):
    """Emit log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "level": record.levelname,
            "name": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def _build_handler() -> logging.Handler:
    handler = logging.StreamHandler(sys.stdout)
    if settings.APP_ENV == "production":
        handler.setFormatter(_JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter("%(asctime)s | %(levelname)-8s | %(name)s | %(message)s")
        )
    return handler


_handler = _build_handler()


def get_logger(name: str) -> logging.Logger:
    """Return a named logger pre-configured with the correct handler."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.addHandler(_handler)
    logger.setLevel(logging.DEBUG if settings.DEBUG else logging.INFO)
    logger.propagate = False
    return logger
