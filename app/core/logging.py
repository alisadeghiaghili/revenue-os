"""
app/core/logging.py — Structured logging setup.

In production (APP_ENV == "production") logs are emitted as JSON so they
can be ingested by log aggregators (Datadog, Loki, CloudWatch).
In all other environments a human-readable format is used.

Usage:
    from app.core.logging import get_logger

    logger = get_logger(__name__)
    logger.info("User created", extra={"user_id": 42})
"""

import logging
import sys
from typing import Optional

_HANDLER_CACHE: Optional[logging.Handler] = None


def _build_handler(app_env: str) -> logging.Handler:
    handler = logging.StreamHandler(sys.stdout)

    if app_env == "production":
        try:
            import json

            class _JsonFormatter(logging.Formatter):
                def format(self, record: logging.LogRecord) -> str:
                    payload = {
                        "level": record.levelname,
                        "name": record.name,
                        "message": record.getMessage(),
                        "time": self.formatTime(record),
                    }
                    if record.exc_info:
                        payload["exc_info"] = self.formatException(record.exc_info)
                    return json.dumps(payload)

            handler.setFormatter(_JsonFormatter())
        except Exception:
            pass  # Fall back to default if anything blows up
    else:
        fmt = logging.Formatter(
            fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler.setFormatter(fmt)

    return handler


def get_logger(name: str) -> logging.Logger:
    """Return a named logger pre-configured with the correct handler.

    The handler is lazily built once and reused for all subsequent calls,
    so calling get_logger multiple times is safe and cheap.
    """
    global _HANDLER_CACHE

    # Lazy import to avoid circular dependency at module load time
    from app.core.config import settings  # noqa: PLC0415

    if _HANDLER_CACHE is None:
        _HANDLER_CACHE = _build_handler(settings.APP_ENV)
        logging.root.setLevel(logging.DEBUG if settings.DEBUG else logging.INFO)
        logging.root.addHandler(_HANDLER_CACHE)

    return logging.getLogger(name)
