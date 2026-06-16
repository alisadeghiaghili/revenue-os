"""
app/core/exceptions.py — Custom application exceptions.

Define domain-specific exception classes here.  Wire them to HTTP responses
via FastAPI exception handlers registered in main.py.
"""


class AppError(Exception):
    """Base class for all application errors."""


class NotFoundError(AppError):
    """Raised when a requested resource does not exist."""


class PermissionDeniedError(AppError):
    """Raised when the caller lacks permission for an action."""


class ConflictError(AppError):
    """Raised when an operation conflicts with existing state."""
