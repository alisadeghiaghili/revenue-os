"""
tests/conftest.py — Shared pytest fixtures.

Add fixtures here that are reused across multiple test modules,
e.g. a test DB session, async HTTP client, or a fake store_id.
"""

import pytest
from httpx import AsyncClient

from main import app


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client() -> AsyncClient:
    """Async test client wired to the FastAPI app."""
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac
