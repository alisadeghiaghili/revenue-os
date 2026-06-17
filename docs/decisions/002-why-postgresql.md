# ADR 002: Why PostgreSQL

**Status:** Accepted  
**Date:** 2026-06-17  

## Context

We need a database that can:
- Handle multi-tenant data isolation
- Support complex analytics queries (JOINs, aggregations)
- Scale to 1000+ stores and millions of orders
- Store both transactional and analytical data

## Decision

We will use **PostgreSQL** as the primary database.

## Rationale

### Pros
- **JSON support:** `JSONB` columns for flexible webhook payloads
- **Mature:** Battle-tested for 25+ years
- **Rich indexing:** B-tree, GIN, partial indexes for multi-tenant queries
- **Window functions:** Essential for time-series analytics (e.g., moving averages)
- **Strong consistency:** ACID guarantees for financial data
- **Cost:** Free, open-source, widely supported on hosting platforms

### Cons
- **Not horizontally scalable out-of-the-box:** Requires sharding for >10k stores (future)
- **Write throughput limits:** Single-master architecture

### Alternatives Considered

| Database | Reason Rejected |
|---|---|
| MongoDB | Weak consistency, no JOINs, harder to enforce multi-tenancy |
| MySQL | Lacks JSONB, weaker analytics support |
| Aurora / CockroachDB | Vendor lock-in, overkill for MVP |

## Consequences

- We can defer sharding until Phase 3 (>1000 stores)
- Analytics queries can run on the same database (no separate OLAP in MVP)
- Backup strategy must be implemented early (`pg_dump` + S3)

## References

- [PostgreSQL Multi-Tenancy Patterns](https://www.citusdata.com/blog/2016/10/03/designing-your-saas-database-for-high-scalability/)
