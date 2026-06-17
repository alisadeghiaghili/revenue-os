# RevenueOS API Specification

**Version:** 1.0.0  
**Base URL:** `https://api.revenueos.io/v1`  
**Protocol:** HTTPS only  
**Format:** JSON (RFC 8259)

---

## Authentication

### 1. Admin Dashboard Access
- **Method:** Bearer token (JWT)
- **Header:** `Authorization: Bearer <token>`
- **Scope:** Full access to store data, insights, settings
- **Expiry:** 24 hours
- **Refresh:** `POST /auth/refresh`

### 2. Shopify Webhook Verification
- **Method:** HMAC-SHA256 signature
- **Header:** `X-Shopify-Hmac-Sha256`
- **Secret:** Store-specific webhook secret
- **Validation:** Server recomputes HMAC from raw body + secret

### 3. OAuth Flow (Shopify Integration)

```
1. User clicks "Connect Shopify"
2. Redirect to:
   https://mystore.myshopify.com/admin/oauth/authorize
     ?client_id={APP_ID}
     &scope=read_orders,read_customers,read_products
     &redirect_uri=https://app.revenueos.io/callback
3. Shopify redirects back with ?code=…
4. Backend exchanges code for access_token via POST /admin/oauth/access_token
5. Store access_token + shop domain in DB
6. Register webhooks programmatically
```

---

## Error Handling (RFC 7807)

All errors return:

```json
{
  "type": "https://api.revenueos.io/errors/validation-error",
  "title": "Invalid request parameters",
  "status": 400,
  "detail": "Field 'start_date' must be ISO 8601 format",
  "instance": "/metrics/revenue?start_date=invalid"
}
```

| Status | Meaning |
|---|---|
| `400` | Bad Request |
| `401` | Unauthorized |
| `403` | Forbidden |
| `404` | Not Found |
| `409` | Conflict (duplicate idempotency key) |
| `422` | Unprocessable Entity (semantic validation failure) |
| `429` | Too Many Requests |
| `500` | Internal Server Error |
| `503` | Service Unavailable (ML pipeline down) |

---

## Rate Limiting

| Endpoint Group | Limit |
|---|---|
| Dashboard API | 1,000 req/hour per user |
| Webhook ingestion | 10,000 req/hour per store |
| ML predictions | 100 req/hour per store |

Response headers:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset: 1718640000
```

---

## Idempotency

Webhook and mutation endpoints support idempotency keys:

```
Idempotency-Key: <UUID>
```

- Keys are stored for **24 hours**
- Duplicate requests return cached response with header `X-Idempotent-Replay: true`

---

## Pagination

Use `limit` and `cursor` for all list endpoints:

```
GET /insights?limit=20&cursor=eyJ…
```

```json
{
  "data": [...],
  "next_cursor": "eyJpZCI6MTIzfQ==",
  "has_more": true
}
```

---

## Endpoints

### 1. Store Integration

#### `POST /stores`
Connect a new store.

**Request:**
```json
{
  "platform": "shopify",
  "shop_domain": "mystore.myshopify.com",
  "access_token": "shpat_…",
  "webhook_secret": "whsec_…"
}
```

**Response: `201 Created`**
```json
{
  "store_id": "str_7KfJ9mP2",
  "platform": "shopify",
  "shop_domain": "mystore.myshopify.com",
  "status": "active",
  "created_at": "2026-06-17T14:23:00Z"
}
```

---

#### `GET /stores/{store_id}`
Retrieve store details.

**Response: `200 OK`**
```json
{
  "store_id": "str_7KfJ9mP2",
  "platform": "shopify",
  "shop_domain": "mystore.myshopify.com",
  "status": "active",
  "last_sync_at": "2026-06-17T14:00:00Z",
  "total_orders": 1248,
  "total_customers": 892
}
```

---

#### `DELETE /stores/{store_id}`
Disconnect store (soft delete — data retained for 30 days).

**Response: `204 No Content`**

---

### 2. Webhook Ingestion

#### `POST /webhooks/shopify/orders/created`
Shopify sends this when a new order is placed.

**Required Headers:**
```
X-Shopify-Hmac-Sha256: <signature>
X-Shopify-Topic: orders/create
X-Shopify-Shop-Domain: mystore.myshopify.com
Idempotency-Key: <order_id>
```

**Request:** (Shopify payload)
```json
{
  "id": 5678901234,
  "order_number": 1001,
  "email": "customer@example.com",
  "created_at": "2026-06-17T14:23:00Z",
  "total_price": "149.99",
  "currency": "USD",
  "line_items": [...],
  "customer": {...}
}
```

**Response: `202 Accepted`**
```json
{
  "event_id": "evt_3kL9pQ",
  "status": "queued"
}
```

---

#### `POST /webhooks/shopify/customers/created`
New customer registered.

**Response: `202 Accepted`**

---

#### `POST /webhooks/shopify/products/updated`
Product info changed.

**Response: `202 Accepted`**

---

### 3. Dashboard Metrics

#### `GET /metrics/revenue`
Revenue over time.

**Query Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `start_date` | ISO 8601 | Yes | Start of period |
| `end_date` | ISO 8601 | Yes | End of period |
| `granularity` | `day` \| `week` \| `month` | No | Default: `day` |

**Response: `200 OK`**
```json
{
  "start_date": "2026-06-01",
  "end_date": "2026-06-17",
  "granularity": "day",
  "currency": "USD",
  "data": [
    { "date": "2026-06-01", "revenue": 3450.00, "orders": 23 },
    { "date": "2026-06-02", "revenue": 4120.50, "orders": 29 }
  ],
  "total_revenue": 58340.00,
  "total_orders": 412
}
```

---

#### `GET /metrics/products/top`
Top-performing products by revenue.

**Query Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `start_date` | ISO 8601 | Yes | Start of period |
| `end_date` | ISO 8601 | Yes | End of period |
| `limit` | integer | No | Default: 10, max: 100 |

**Response: `200 OK`**
```json
{
  "products": [
    {
      "product_id": "prd_8x3K",
      "name": "Premium Widget",
      "revenue": 12450.00,
      "units_sold": 83,
      "margin": 0.42
    }
  ]
}
```

---

#### `GET /metrics/customers/cohorts`
Cohort retention analysis.

**Query Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `cohort_month` | `YYYY-MM` | Yes | Month to analyze |

**Response: `200 OK`**
```json
{
  "cohort_month": "2026-05",
  "cohort_size": 124,
  "retention": [
    { "month_offset": 0, "customers": 124, "rate": 1.0 },
    { "month_offset": 1, "customers": 87,  "rate": 0.70 },
    { "month_offset": 2, "customers": 64,  "rate": 0.52 }
  ]
}
```

---

### 4. AI Insights & Predictions

#### `GET /insights`
Recent AI-generated insights.

**Query Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `limit` | integer | No | Default: 10 |
| `category` | `anomaly` \| `opportunity` \| `churn` \| `forecast` | No | Filter by category |

**Response: `200 OK`**
```json
{
  "insights": [
    {
      "insight_id": "ins_9mK2",
      "category": "anomaly",
      "severity": "high",
      "title": "Revenue drop detected",
      "description": "Daily revenue dropped 23% compared to 7-day average.",
      "created_at": "2026-06-17T14:05:00Z",
      "actions": [
        "Check inventory for top products",
        "Review marketing campaign performance"
      ]
    }
  ]
}
```

---

#### `POST /predictions/clv`
Predict customer lifetime value.

**Request:**
```json
{ "customer_id": "cus_4xL9" }
```

**Response: `200 OK`**
```json
{
  "customer_id": "cus_4xL9",
  "predicted_clv": 2450.00,
  "confidence": 0.87,
  "model_version": "clv-xgb-v2.1",
  "computed_at": "2026-06-17T14:23:00Z"
}
```

---

#### `POST /predictions/churn`
Predict churn risk.

**Request:**
```json
{ "customer_id": "cus_4xL9" }
```

**Response: `200 OK`**
```json
{
  "customer_id": "cus_4xL9",
  "churn_probability": 0.34,
  "risk_level": "medium",
  "factors": [
    "No purchase in 45 days",
    "Declining order frequency"
  ],
  "model_version": "churn-lr-v1.3",
  "computed_at": "2026-06-17T14:23:00Z"
}
```

---

#### `GET /predictions/forecast/revenue`
Revenue forecast for the next 30 days.

**Response: `200 OK`**
```json
{
  "forecast_start": "2026-06-18",
  "forecast_end": "2026-07-18",
  "model": "prophet-v1.0",
  "data": [
    {
      "date": "2026-06-18",
      "predicted_revenue": 3800.00,
      "lower_bound": 3200.00,
      "upper_bound": 4400.00
    }
  ]
}
```

---

### 5. Health & Status

#### `GET /health`
Service health check.

**Response: `200 OK`**
```json
{
  "status": "healthy",
  "services": {
    "database": "up",
    "redis": "up",
    "celery": "up",
    "ml_pipeline": "up"
  },
  "timestamp": "2026-06-17T14:23:00Z"
}
```

---

## Outbound Webhooks

RevenueOS can notify your systems when key events occur.

#### `POST <your_url>` — `insight.created`

```json
{
  "event": "insight.created",
  "insight_id": "ins_9mK2",
  "category": "anomaly",
  "severity": "high",
  "created_at": "2026-06-17T14:05:00Z"
}
```

---

## Notes

- All timestamps are **UTC** in ISO 8601 format
- Currency codes follow **ISO 4217**
- Webhook payloads are idempotent by design
- ML models retrained **weekly** (Sunday 02:00 UTC)
- Feature store updated **hourly**
