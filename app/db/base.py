"""
app/db/base.py — Declarative base for all ORM models.

Import all model modules here so Alembic's autogenerate can discover them:

    from app.db.base import Base  # noqa: F401
    from app.models import revenue  # noqa: F401
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Shared declarative base.  All ORM models must inherit from this."""
