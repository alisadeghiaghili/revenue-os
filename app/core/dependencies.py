"""
app/core/dependencies.py — Shared FastAPI dependency functions.

All repository methods must filter every query by store_id to enforce
tenant isolation.  Inject `store_id` via the `get_store_id` dependency
into any endpoint that touches tenant-scoped data.
"""

from fastapi import HTTPException, Request


async def get_store_id(request: Request) -> str:
    """Extract and validate the tenant identifier from the request header.

    Reads the ``X-Store-ID`` header from the incoming request.  Raises a
    403 if the header is absent or empty.

    All repository methods must filter every query by store_id to enforce
    tenant isolation.

    Args:
        request: The current FastAPI ``Request`` object.

    Returns:
        The store ID string.

    Raises:
        HTTPException: 403 if the header is missing or blank.
    """
    store_id = request.headers.get("X-Store-ID", "").strip()
    if not store_id:
        raise HTTPException(status_code=403, detail="store_id is required")
    return store_id
