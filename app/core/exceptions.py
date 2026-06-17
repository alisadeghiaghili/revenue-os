"""
Application-level exception classes.

Raise these inside service / repository layers; the global exception
handlers in main.py translate them into appropriate HTTP responses.
"""


class AppError(Exception):
    """Base class for all application errors."""


class NotFoundError(AppError):
    """Raised when a requested resource does not exist."""


class PermissionDeniedError(AppError):
    """Raised when the caller lacks permission for an action."""


class ConflictError(AppError):
    """Raised when an operation violates a uniqueness constraint."""
