"""
Shared pytest fixtures.

Add async DB fixtures, test client factory, and mock store_id header here.
"""

import pytest
from httpx import AsyncClient

from main import app


@pytest.fixture
async def client() -> AsyncClient:
    """Async HTTP test client wired to the FastAPI app."""
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac
