"""
app/core/config.py — Centralised settings loader.

All configuration is loaded from the .env file (or real environment variables)
via pydantic-settings.  Import the singleton `settings` wherever you need
access to configuration values:

    from app.core.config import settings
    print(settings.DATABASE_URL)

Do **not** read os.environ directly in other modules.
"""

from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False,
        extra="ignore",
    )

    # ── database ─────────────────────────────────────────────────────────────
    DATABASE_URL: str

    @field_validator("DATABASE_URL")
    @classmethod
    def database_url_must_be_postgres(cls, v: str) -> str:
        if not v.startswith("postgresql"):
            raise ValueError("DATABASE_URL must start with 'postgresql'")
        return v

    # ── redis / celery ────────────────────────────────────────────────────────
    REDIS_URL: str
    CELERY_BROKER_URL: str
    CELERY_RESULT_BACKEND: str

    # ── app ───────────────────────────────────────────────────────────────────
    SECRET_KEY: str
    DEBUG: bool = False
    APP_ENV: str = "development"

    # ── cors ──────────────────────────────────────────────────────────────────
    # Comma-separated list of allowed origins, e.g. "http://localhost:3000"
    CORS_ORIGINS: List[str] = ["*"]


# Module-level singleton — import this, not the class.
settings = Settings()
