"""
Revenue OS — FastAPI application entry point.

Usage:
    uvicorn main:app --reload

All routers are registered here. Startup/shutdown hooks manage the
database connection lifecycle via SQLAlchemy async engine.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.logging import get_logger
from app.db.session import engine

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage DB connection pool on startup and shutdown."""
    logger.info("Starting up — connecting to database")
    yield
    logger.info("Shutting down — disposing database engine")
    await engine.dispose()


app = FastAPI(
    title="Revenue OS",
    version="0.1.0",
    description="Multi-tenant revenue operations backend.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.DEBUG else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# TODO: include routers here
# from app.api.v1 import router as v1_router
# app.include_router(v1_router, prefix="/api/v1")


@app.get("/health", tags=["ops"])
async def health_check():
    """Liveness probe used by load balancers and orchestrators."""
    return {"status": "ok", "env": settings.APP_ENV}
