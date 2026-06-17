# Multi-Tenancy Strategy

## Overview

RevenueOS is a **shared-database, shared-schema** multi-tenant architecture. All tenants (stores) share the same PostgreSQL database and tables, with strict isolation enforced via `store_id`.

## Design Principles

### 1. Every Table Has `store_id`
Every table (except system tables) includes a `store_id` column that references `stores.id`.

### 2. Every Query Filters by `store_id`
All SQLAlchemy queries must filter by `store_id`. No exceptions.

```python
# ✅ CORRECT
orders = db.query(Order).filter(Order.store_id == current_store_id).all()

# ❌ WRONG (would leak data across tenants)
orders = db.query(Order).all()
```

### 3. Unique Constraints Include `store_id`

```sql
UNIQUE(store_id, external_id)  -- not just UNIQUE(external_id)
```

This allows different stores to have overlapping `external_id` values from their respective platforms.

### 4. Foreign Keys Respect Tenant Boundaries
When joining tables, always include `store_id` in the JOIN condition:

```python
# ✅ CORRECT
query = (
    db.query(Order, Customer)
    .join(Customer,
          and_(Order.customer_id == Customer.id,
               Order.store_id == Customer.store_id))
    .filter(Order.store_id == current_store_id)
)
```

### 5. Row-Level Security (RLS) — Future Enhancement
For additional safety, we can enable PostgreSQL RLS:

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY orders_isolation_policy ON orders
    USING (store_id = current_setting('app.current_store_id')::uuid);
```

This is not implemented in MVP but recommended for Phase 2.

---

## API Authentication Flow

1. User logs in → receives JWT token with `store_id` claim
2. Every API request includes JWT in `Authorization` header
3. FastAPI middleware validates JWT and extracts `store_id`
4. `store_id` is injected into request context
5. All database queries use `context.store_id`

## Webhook Flow

1. Webhook arrives at `/webhooks/{platform}/{event_type}`
2. HMAC signature verified against `webhook_secret`
3. Lookup store by `shop_domain` from webhook payload
4. All subsequent queries scoped to that `store_id`

---

## Testing Multi-Tenancy

Every test must create isolated stores and verify data isolation:

```python
def test_customer_isolation():
    store_a = create_test_store("store-a")
    store_b = create_test_store("store-b")

    customer_a = create_customer(store_a.id, email="test@example.com")
    customer_b = create_customer(store_b.id, email="test@example.com")

    # Same email, different stores
    assert customer_a.id != customer_b.id

    # Query isolation
    customers_a = get_customers(store_a.id)
    assert len(customers_a) == 1
    assert customer_b.id not in [c.id for c in customers_a]
```

---

## Common Pitfalls

### ❌ Forgetting to filter by `store_id`

```python
# BAD: Will return ALL customers across ALL stores
customers = db.query(Customer).filter(Customer.email == email).all()
```

### ✅ Always scope queries

```python
# GOOD: Returns only customers for current store
customers = db.query(Customer).filter(
    Customer.store_id == store_id,
    Customer.email == email
).all()
```

### ❌ Using global caches without `store_id`

```python
# BAD: Cache key collision across stores
cache_key = f"customer:{customer_id}"
```

### ✅ Include `store_id` in cache keys

```python
# GOOD: Cache keys are tenant-specific
cache_key = f"store:{store_id}:customer:{customer_id}"
```

---

## Performance Considerations

- **Indexes:** All indexes on filtered columns must be composite: `(store_id, column)`
- **Partitioning (future):** For very large tables, partition by `store_id` ranges
- **Connection Pooling:** Each worker shares connection pool, no per-tenant connections

---

## Security Checklist

- [ ] Every table has `store_id`
- [ ] All queries filter by `store_id`
- [ ] API middleware injects `store_id` from JWT
- [ ] Webhook handlers validate signature before lookup
- [ ] Cache keys include `store_id`
- [ ] Tests verify cross-tenant isolation
- [ ] Celery tasks accept `store_id` as parameter

---

**Last Updated:** 2026-06-17
