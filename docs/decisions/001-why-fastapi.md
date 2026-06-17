# ADR 001: Why FastAPI

**Status:** Accepted  
**Date:** 2026-06-17  
**Deciders:** Technical Architecture Lead

## Context

We need a backend framework for RevenueOS that can handle:
- High-throughput webhook ingestion (1000s of requests/day per store)
- Complex async tasks (ML inference, data aggregation)
- Auto-generated API documentation
- Type safety for collaboration across team

## Decision

We will use **FastAPI** as the backend framework.

## Rationale

### Pros
- **Async by default:** Native support for `async/await`, critical for webhook handling
- **Type safety:** Pydantic models provide runtime validation + editor autocomplete
- **Auto-docs:** OpenAPI/Swagger UI out of the box
- **Performance:** One of the fastest Python frameworks (Starlette + uvicorn)
- **Modern:** Built for Python 3.11+ with type hints
- **Team familiarity:** Both backend engineers have production experience with FastAPI

### Cons
- **Smaller ecosystem than Flask/Django:** Fewer plugins, but core needs are met
- **Learning curve for async:** Team must understand async patterns

### Alternatives Considered

| Framework | Reason Rejected |
|---|---|
| Django + DRF | Too heavyweight, ORM lock-in, not async-first |
| Flask | Mature but lacks native async, type safety, auto-docs |
| Node.js (Express) | Wrong language, team lacks Node expertise |

## Consequences

- All API endpoints will use `async def` by default
- Database queries must use async drivers (`asyncpg` or SQLAlchemy async)
- We commit to Python 3.11+ for the project lifetime

## References

- [FastAPI Docs](https://fastapi.tiangolo.com/)
- [FastAPI Async SQL](https://fastapi.tiangolo.com/tutorial/sql-databases/)
