"""
main.py — Application entry point.

Creates the FastAPI instance, registers middleware, includes routers,
and manages the DB connection lifecycle via startup/shutdown events.

Usage:
    uvicorn main:app --reload
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── startup ──────────────────────────────────────────────────────────────
    logger.info("Starting Revenue OS [env=%s]", settings.APP_ENV)
    # TODO: initialise DB connection pool here
    yield
    # ── shutdown ─────────────────────────────────────────────────────────────
    logger.info("Shutting down Revenue OS")
    # TODO: dispose DB connection pool here


app = FastAPI(
    title="Revenue OS",
    version="0.1.0",
    description="Multi-tenant revenue management backend.",
    lifespan=lifespan,
)

# ── CORS ─────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
# TODO: include routers here
# from app.api.v1 import router as v1_router
# app.include_router(v1_router, prefix="/api/v1")


# ── Health check ─────────────────────────────────────────────────────────────
@app.get("/health", tags=["meta"])
async def health_check():
    return {"status": "ok", "env": settings.APP_ENV}
