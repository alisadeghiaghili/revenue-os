"""
Shared FastAPI dependencies.

All repository methods must filter every query by store_id to enforce
tenant isolation.
"""

from fastapi import HTTPException, Request


async def get_store_id(request: Request) -> str:
    """
    Extract the tenant identifier from the X-Store-ID request header.

    All repository methods must filter every query by store_id to enforce
    tenant isolation.

    Raises:
        HTTPException(403): if the header is missing or empty.
    """
    store_id = request.headers.get("X-Store-ID", "").strip()
    if not store_id:
        raise HTTPException(status_code=403, detail="store_id is required")
    return store_id
