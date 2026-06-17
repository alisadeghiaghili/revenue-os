"""
Declarative base shared by all ORM models.

Import this in every model module so that Alembic's autogenerate can
discover all tables via metadata.
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
