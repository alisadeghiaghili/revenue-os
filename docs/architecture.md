# RevenueOS Architecture

## Overview

RevenueOS is an AI-powered revenue intelligence copilot for e-commerce platforms. The system ingests transactional data via webhooks, processes it through ML pipelines, generates natural language insights using LLMs, and presents actionable recommendations through a modern web dashboard.

---

## System Components

### 1. Frontend Layer
**Tech:** Next.js 14+, Tailwind CSS, shadcn/ui  
**Host:** Vercel  
**Responsibilities:**
- Real-time revenue dashboard
- AI-generated insight feed
- Alert notifications
- Store connection management
- User authentication (clerk/auth0)

**Key Routes:**
- `/dashboard` — overview metrics
- `/insights` — AI recommendations
- `/customers` — CLV, cohorts, segments
- `/products` — performance analysis
- `/settings` — integrations, API keys

---

### 2. Backend API Layer
**Tech:** FastAPI, Python 3.11+  
**Host:** Railway / Render  
**Responsibilities:**
- RESTful API endpoints
- Webhook ingestion (Shopify, WooCommerce)
- Authentication & multi-tenancy
- Background job orchestration
- LLM prompt orchestration

**Core Modules:**
- `app/api/webhooks.py` — webhook receivers
- `app/api/stores.py` — store CRUD
- `app/api/insights.py` — insight retrieval
- `app/services/ingestion.py` — data normalization
- `app/services/llm.py` — GPT-4o-mini integration

---

### 3. Database Layer
**Tech:** PostgreSQL 15+  
**Host:** Railway / Supabase / Neon  
**Schema Design:**
- **Raw tables:** `orders`, `customers`, `products`, `order_items`
- **Feature tables:** `customer_features`, `daily_metrics`
- **Insight tables:** `insights`, `alerts`
- **System tables:** `stores`, `webhooks_log`

**Indexes:**
- `orders(store_id, created_at)`
- `customers(store_id, email)`
- `customer_features(store_id, customer_id)`

---

### 4. Background Processing Layer
**Tech:** Celery, Redis  
**Host:** Railway / Render (worker dyno)  
**Job Types:**

| Job | Schedule | Purpose |
|---|---|---|
| `calculate_clv` | Daily 02:00 UTC | Customer lifetime value |
| `detect_anomalies` | Hourly | Revenue spike/drop detection |
| `cohort_analysis` | Weekly | Retention & churn metrics |
| `churn_prediction` | Daily | At-risk customer identification |
| `generate_insights` | Daily 06:00 UTC | LLM-based recommendations |

---

### 5. ML/Analytics Layer
**Tech:** scikit-learn, XGBoost, Prophet  
**Models:**
- **CLV:** XGBoost regression on RFM + behavioral features
- **Churn:** Binary classification (logistic regression / XGBoost)
- **Anomaly Detection:** Isolation Forest + statistical thresholds
- **Forecasting:** Prophet for revenue/demand prediction

**Feature Engineering:**

```python
# Customer-level features
- recency, frequency, monetary (RFM)
- avg_order_value, total_orders, total_revenue
- days_since_last_order, purchase_interval_stddev
- product_category_diversity
```

---

### 6. LLM Insight Generation
**Tech:** OpenAI GPT-4o-mini  
**Prompt Strategy:**

```python
system_prompt = """
You are a revenue growth advisor for e-commerce stores.
Generate 1-2 sentence actionable insights from metrics.
Focus on: customer retention, product performance, revenue optimization.
"""

user_prompt = f"""
Store: {store_name}
Period: Last 7 days
Metrics:
- Revenue: ${revenue} ({change}%)
- Top product: {product_name} (${product_revenue})
- Churn risk: {churn_count} customers
- CLV trend: {clv_trend}

Generate 2 insights.
"""
```

**Output Format:**

```json
{
  "insights": [
    {
      "type": "churn_alert",
      "severity": "high",
      "title": "23 high-value customers at risk",
      "description": "...",
      "action": "Launch win-back campaign with 15% discount"
    }
  ]
}
```

---

## Data Flow

### Webhook Ingestion Flow

```
Shopify/WooCommerce
↓ (webhook: order/create, customer/update)
FastAPI /webhooks/{platform}/{event}
↓ (validate signature, deduplicate)
PostgreSQL raw insert
↓ (log to webhooks_log)
Celery task: process_order(order_id)
↓ (feature extraction, aggregation)
PostgreSQL feature tables
↓ (trigger ML jobs if threshold met)
ML pipeline execution
↓
Insight generation (LLM)
↓
Frontend polling /api/insights
```

### Real-time Dashboard Flow

```
User opens /dashboard
↓
Next.js SSR fetch /api/stores/{store_id}/metrics
↓
FastAPI query PostgreSQL aggregates
↓
Return JSON {revenue, orders, top_products, ...}
↓
shadcn/ui charts render
```

---

## Infrastructure

### Deployment Architecture

```
┌─────────────────────────────────────────┐
│ Cloudflare DNS + CDN                    │
└────────────┬─────────────────────────────┘
             │
     ┌──────┴───────┐
     │               │
┌───┴────┐      ┌────┴─────┐
│ Vercel │      │ Railway   │
│Next.js │◄─────┤ FastAPI   │
└────────┘      │ + Celery  │
                 └─────┬────┘
                      │
          ┌───────┴───────┐
          │               │
  ┌─────┴───┐   ┌─────┴────┐
  │PostgreSQL│   │  Redis   │
  │ (Neon)   │   │ (Upstash)│
  └──────────┘   └──────────┘
```

### External Services
- **Object Storage:** Cloudflare R2 (exports, reports)
- **Email:** Resend / SendGrid (weekly reports)
- **Monitoring:** Sentry (errors), Posthog (analytics)
- **Secrets:** Vercel env vars, Railway env vars

---

## Security

### Authentication
- Frontend: Clerk / Auth0 JWT
- API: Bearer token validation
- Webhook: HMAC signature verification (per platform)

### Multi-tenancy
- All tables include `store_id` (indexed)
- Row-level security via FastAPI middleware
- API keys scoped to single store

### Data Protection
- Webhook payload encrypted at rest
- PII hashed where possible
- GDPR-compliant deletion endpoints

---

## Scalability Considerations

| Component | Current | Scale Strategy |
|---|---|---|
| FastAPI | 1 instance | Horizontal (Railway replicas) |
| Celery | 1 worker | Add workers per queue |
| PostgreSQL | Single DB | Read replicas, partitioning by store_id |
| Redis | Single instance | Redis Cluster for job queues |

**Webhook Rate Limiting:**
- 100 req/sec per store
- Exponential backoff on ingestion errors
- Dead-letter queue for failed webhooks

---

## Development Workflow

### Local Setup

```bash
# Backend
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload

# Frontend
cd frontend
npm install
npm run dev

# Background worker
celery -A app.workers.celery_app worker -l info
```

### Testing Strategy
- **Unit:** pytest for FastAPI routes, ML functions
- **Integration:** Webhook replay tests with fixtures
- **E2E:** Playwright for critical dashboard flows

---

## Monitoring & Observability

### Metrics
- Webhook ingestion rate (req/sec)
- Celery job success rate (%)
- LLM API latency (ms)
- Database query time (p95)

### Alerts
- Webhook processing delay > 5 min
- Celery queue depth > 1000
- PostgreSQL connection pool exhaustion
- OpenAI API 429 rate limit

---

## Future Architecture Improvements

1. **Event Sourcing:** Migrate from direct DB writes to event log (Kafka/NATS)
2. **Real-time Streaming:** Replace polling with WebSocket for live metrics
3. **Microservices:** Split ingestion, analytics, insight generation into separate services
4. **ML Model Registry:** MLflow for versioning and A/B testing models
5. **Multi-region:** Deploy to EU for GDPR customers

---

## References

- [ADR 003: Webhook Idempotency](./decisions/003-webhook-idempotency.md)
- [Database Schema](./database-schema.sql)
- [API Specification](./api-spec.md)
