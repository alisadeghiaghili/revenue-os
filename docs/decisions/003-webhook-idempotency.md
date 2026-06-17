# ADR 003: Webhook Idempotency Architecture

**Status:** Accepted  
**Date:** 2025-06-17  
**Authors:** Ali Aghili  
**Context:** RevenueOS / Revlytics AI  

---

## Context

RevenueOS integrates with multiple e-commerce platforms (Shopify, WooCommerce) via webhooks to receive real-time events for orders, customers, and products. Webhooks can be:

- **Duplicated** due to network retries or platform behavior
- **Replayed** during reconnection or failure recovery
- **Reordered** due to async delivery

Without idempotency guarantees, duplicate processing can lead to:
- Inflated revenue metrics
- Duplicate customer records
- Incorrect churn calculations
- Broken analytics pipelines

We need a **production-grade, auditable, and horizontally scalable** solution to ensure **exactly-once processing** of webhook events.

---

## Decision

We adopt a **two-phase async architecture** using PostgreSQL as the authoritative source of truth:

### Phase 1: Synchronous Deduplication (API Layer)
- Incoming webhook is **immediately logged** into the `webhooks_log` table
- A **composite unique constraint** on `(store_id, webhook_id)` enforces database-level deduplication
- If duplicate, the insert fails with `409 Conflict` → we still return `200 OK` to the platform
- Celery task is enqueued **only if insert succeeds**

### Phase 2: Asynchronous Processing (Worker Layer)
- Celery worker picks up the task
- Processes the payload (e.g., upsert to `orders`, `customers`, etc.)
- Updates `processed_at` timestamp in `webhooks_log` upon completion
- If processing fails, task is retried with exponential backoff; row remains in `pending` state for monitoring

### Database Schema

```sql
CREATE TABLE webhooks_log (
    id BIGSERIAL PRIMARY KEY,
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    webhook_id VARCHAR(255) NOT NULL,  -- Platform-provided unique ID (e.g., Shopify webhook ID)
    event_type VARCHAR(100) NOT NULL,  -- e.g., 'orders/create', 'customers/update'
    payload JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    retry_count INT DEFAULT 0,
    error_message TEXT,

    CONSTRAINT unique_webhook_per_store UNIQUE (store_id, webhook_id)
);

CREATE INDEX idx_webhooks_pending ON webhooks_log (store_id, received_at)
    WHERE processed_at IS NULL;

CREATE INDEX idx_webhooks_event_type ON webhooks_log (event_type);
```

---

## Rationale

### Why PostgreSQL Unique Constraint?
- **Atomic guarantee**: No race condition possible at database level
- **Persistent audit trail**: Every webhook attempt is logged, even duplicates
- **No external dependencies**: No Redis, no distributed locks
- **Crash-safe**: Survives pod restarts, network partitions, Kubernetes evictions

### Why Two-Phase (Sync + Async)?
- **Fast webhook acknowledgment**: We return `200 OK` to Shopify/WooCommerce within <50ms to avoid timeout retries
- **Resilient processing**: If business logic fails (DB timeout, external API down), we can retry without re-receiving the webhook
- **Observability**: Clear separation between "received" and "processed" states

### Why Celery?
- **Built-in retry logic** with exponential backoff
- **Dead-letter queue** for failed tasks
- **Priority queues** for critical vs. batch events
- **Horizontal scaling**: Add workers without code changes

---

## Alternatives Considered

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **Redis SET with TTL** | Fast in-memory lookup | Lost on restart; no audit trail | ❌ Rejected |
| **PostgreSQL Advisory Locks** | Lightweight | Complex deadlock scenarios; no persistence | ❌ Rejected |
| **Application-level deduplication** | Simple to implement | Race conditions under load | ❌ Rejected |
| **Outbox Pattern** | Event sourcing benefits | Over-engineered for current scale | 🔄 Future consideration |

---

## Monitoring & Observability

### Health Check Query

```sql
SELECT
    event_type,
    COUNT(*) FILTER (WHERE processed_at IS NULL AND received_at < NOW() - INTERVAL '5 minutes') AS stuck_webhooks,
    COUNT(*) FILTER (WHERE retry_count > 3) AS high_retry_count,
    AVG(EXTRACT(EPOCH FROM (processed_at - received_at))) AS avg_processing_time_seconds
FROM webhooks_log
WHERE received_at > NOW() - INTERVAL '1 hour'
GROUP BY event_type;
```

### Prometheus Metrics
- `webhooks_received_total{store_id, event_type}`
- `webhooks_processed_total{store_id, event_type, status}`
- `webhooks_processing_duration_seconds{event_type}`
- `webhooks_queue_depth{event_type}`

### Alert Triggers
- **Critical**: Webhooks unprocessed for >15 minutes
- **Warning**: Retry count >5 for any event
- **Info**: Processing time >30s for any event type

---

## Implementation Checklist

- [ ] Create `webhooks_log` table with composite unique constraint
- [ ] Implement FastAPI endpoint with `try/except IntegrityError` for duplicate handling
- [ ] Configure Celery worker with retry policy (`max_retries=5`, `backoff=2^n`)
- [ ] Add Prometheus metrics to FastAPI and Celery
- [ ] Deploy Grafana dashboard for webhook monitoring
- [ ] Write integration test simulating duplicate webhook delivery

---

## Consequences

### Positive
- ✅ **Zero duplicate processing** guaranteed at database level
- ✅ **Full audit trail** for debugging and compliance
- ✅ **Horizontally scalable** (add more Celery workers)
- ✅ **Platform-agnostic** (works for Shopify, WooCommerce, Stripe, etc.)

### Negative
- ⚠️ **Database writes on every webhook** (acceptable for <10K/day scale)
- ⚠️ **Requires webhook ID from platform** (fallback: hash payload if missing)

### Mitigation
- For high-volume stores (>100K webhooks/day), consider **partitioning** `webhooks_log` by `received_at`
- For platforms without webhook IDs, generate deterministic hash: `SHA256(store_id || event_type || payload)`

---

## References

- [Shopify Webhook Best Practices](https://shopify.dev/docs/apps/webhooks/best-practices)
- [WooCommerce Webhook Delivery](https://woocommerce.github.io/woocommerce-rest-api-docs/#webhooks)
- [Idempotency Keys in Stripe API](https://stripe.com/docs/api/idempotent_requests)
- [PostgreSQL Constraints Documentation](https://www.postgresql.org/docs/current/ddl-constraints.html)
- [Celery Task Retries](https://docs.celeryproject.org/en/stable/userguide/tasks.html#retrying)
