# RevenueOS: Project Blueprint

**Last Updated:** 1405/03/27 (2026-06-17)  
**Status:** Architecture Finalized, Ready for Implementation

---

## 1. Product Definition

### Product Identity
- **Name:** RevenueOS
- **Tagline:** AI Co-pilot for E-commerce Revenue Growth
- **Positioning:** An AI advisor that turns raw commerce data into actionable revenue-growth decisions
- **Key Differentiator:** Not a traditional BI dashboard—this is an intelligent decision engine

### Core Value Proposition
Transform complex e-commerce data into clear, actionable recommendations that drive revenue growth without requiring analytics expertise.

---

## 2. Target Users

### Phase 1: Primary Persona - Sarah
- **Role:** Shopify store owner
- **Revenue:** ~$100k/month
- **Technical Level:** Non-technical
- **Pain Points:**
  - Google Analytics 4 is too complex and overwhelming
  - Cannot determine which products are actually profitable
  - Cannot explain sudden sales drops
  - Cannot identify or retain repeat customers
  - Lacks actionable insights from existing data
- **Desired Outcomes:**
  - Weekly summary emails with clear insights
  - Automated anomaly alerts
  - Specific recommendations on what to promote
  - Understanding of customer retention patterns

### Phase 2: Secondary Persona - Ahmad
- **Role:** WooCommerce store manager
- **Revenue:** ~$500k/month
- **Technical Level:** Moderate
- **Platform:** WooCommerce

---

## 3. Technical Architecture

### 3.1 Frontend Stack
- **Framework:** Next.js (App Router)
- **Styling:** Tailwind CSS
- **Component Library:** shadcn/ui
- **Charts:** Recharts
- **State Management:** Zustand or Jotai
- **Deployment:** Vercel

### 3.2 Backend Stack
- **Framework:** FastAPI (Python)
- **Database:** PostgreSQL (primary datastore)
- **Cache:** Redis
- **Task Queue:** Celery + Redis
- **Deployment:** Railway or Render

### 3.3 Infrastructure
- **Frontend Hosting:** Vercel
- **Backend Hosting:** Railway/Render
- **Object Storage:** Cloudflare R2
- **CDN:** Cloudflare
- **Monitoring:** Sentry

### 3.4 ML/Analytics Stack
- **Libraries:**
  - scikit-learn
  - XGBoost
  - Prophet (time-series forecasting)
- **Feature Store:** PostgreSQL tables
- **Use Cases:**
  - Customer Lifetime Value (CLV) prediction
  - Churn scoring
  - Anomaly detection
  - Product association rules
  - Sales forecasting

### 3.5 Platform Integrations

#### Phase 1: Shopify
- Shopify Admin API
- Shopify Webhooks
- Key Events:
  - `orders/create`
  - `orders/updated`
  - `customers/create`
  - `customers/update`
  - `products/create`
  - `products/update`

#### Phase 2: WooCommerce
- WooCommerce REST API
- WooCommerce Webhooks

---

## 4. Data Architecture

### 4.1 Multi-Tenant Model
- **Pattern:** Shared database, row-level isolation
- **Tenant Key:** `store_id` (required on all tables)
- **Indexing Strategy:** Composite indexes with `store_id` prefix

### 4.2 Core Database Schema

#### Core Tables

```sql
-- Stores (tenants)
stores (
  id, name, platform, timezone, currency,
  shopify_domain, access_token, webhook_secret,
  created_at, updated_at
)

-- Orders
orders (
  id, store_id, external_id, customer_id,
  order_number, total_amount, currency,
  line_items (JSONB), status,
  created_at, updated_at
)

-- Customers
customers (
  id, store_id, external_id, email,
  first_name, last_name, phone,
  total_spent, order_count,
  first_order_at, last_order_at,
  created_at, updated_at
)

-- Products
products (
  id, store_id, external_id, title,
  vendor, product_type, price,
  inventory_quantity, status,
  created_at, updated_at
)

-- Events (analytics)
events (
  id, store_id, event_type, entity_type,
  entity_id, payload (JSONB),
  created_at
)
```

#### Supporting Tables

```sql
-- Webhook log (idempotency)
webhooks_log (
  id, store_id, webhook_id, topic,
  payload (JSONB), status,
  processed_at, created_at,
  UNIQUE(store_id, webhook_id)
)

-- ML predictions
predictions (
  id, store_id, model_type, entity_type,
  entity_id, prediction_value, confidence,
  created_at
)
```

### 4.3 Standard Views
- `active_stores_summary`: aggregated store health metrics
- `customer_360`: unified customer view with CLV, RFM scores
- `product_performance`: revenue, margin, and velocity metrics

---

## 5. Key Technical Decisions

### ADR 003: Idempotent Webhook Architecture

**Status:** Accepted  
**Date:** 1405/03/27

#### Context
E-commerce platforms may send duplicate webhooks due to retries, network issues, or operational incidents. Processing duplicates would corrupt analytics and trigger incorrect ML predictions.

#### Decision
Implement a **two-phase async webhook processing architecture**:

**Phase 1: Synchronous Ingestion**
- Accept webhook HTTP request
- Immediately log to `webhooks_log` table
- Use composite unique constraint: `(store_id, webhook_id)`
- Return 200 OK instantly
- Enqueue Celery task for async processing

**Phase 2: Asynchronous Processing**
- Celery worker picks up task
- Validates payload schema
- Extracts entities (order, customer, product)
- Upserts to domain tables with conflict resolution
- Updates `webhooks_log.status` and `processed_at`
- Implements retry logic with exponential backoff

#### Consequences
✅ **Guarantees exactly-once processing**  
✅ **Fast webhook acknowledgment (<100ms)**  
✅ **Audit trail for debugging**  
✅ **Graceful handling of platform retries**  
⚠️ **Adds complexity to deployment (requires Celery workers)**

---

## 6. ML Pipeline Design

### 6.1 Processing Flow
1. **Webhook ingestion** → FastAPI endpoint
2. **Data validation** → Pydantic models
3. **Storage** → PostgreSQL domain tables
4. **Feature engineering** → Scheduled Celery tasks
5. **Model training** → Weekly batch jobs
6. **Inference** → On-demand + scheduled scoring
7. **Insight generation** → Rule engine + ML outputs

### 6.2 ML Use Cases

| Use Case | Model Type | Input Features | Output | Trigger |
|---|---|---|---|---|
| CLV Prediction | XGBoost Regressor | RFM, AOV, order frequency | CLV score + confidence | New order |
| Churn Risk | XGBoost Classifier | Days since last order, frequency trend | Churn probability | Daily batch |
| Anomaly Detection | Prophet + IQR | Daily revenue time series | Anomaly flag + severity | Real-time |
| Product Association | Apriori | Order line items | Frequently bought together | Weekly |

---

## 7. API Design

### 7.1 Core Endpoints

#### Authentication

```
POST   /api/v1/auth/shopify/install
POST   /api/v1/auth/shopify/callback
POST   /api/v1/auth/logout
```

#### Webhooks

```
POST   /api/v1/webhooks/shopify
POST   /api/v1/webhooks/woocommerce
```

#### Analytics

```
GET    /api/v1/analytics/revenue?period=30d
GET    /api/v1/analytics/customers?segment=high_value
GET    /api/v1/analytics/products/top?metric=revenue
```

#### Insights

```
GET    /api/v1/insights?type=anomaly&status=unread
POST   /api/v1/insights/:id/actions
```

---

## 8. Repository Structure

```
revenueos/
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── db/
│   │   ├── ml/
│   │   ├── services/
│   │   └── workers/
│   ├── alembic/
│   ├── tests/
│   └── requirements.txt
├── frontend/
│   ├── app/
│   ├── components/
│   ├── lib/
│   └── public/
├── docs/
│   ├── decisions/
│   ├── api-spec.md
│   └── architecture.md
├── infra/
│   ├── terraform/
│   └── docker/
└── README.md
```

---

## 9. Development Process

### Commit Message Convention

**Short Format (preferred):**

```
feat: add webhook idempotency check
fix: resolve duplicate order processing
docs: update ADR-003 with retry logic
```

**Long Format (complex changes):**

```
feat(webhooks): implement two-phase async processing

- Add webhooks_log table with unique constraint
- Create Celery task for order processing
- Add retry logic with exponential backoff

Closes #42
```

---

## 10. Success Metrics

### Product Metrics
- **Weekly Active Users (WAU)**
- **Insight Action Rate:** % of insights acted upon
- **Time to First Value:** hours from signup to first insight
- **Retention:** Day 7, Day 30 retention rates

### Technical Metrics
- **Webhook Processing Latency:** p95 < 100ms (sync phase)
- **Data Freshness:** < 5 minutes from event to dashboard
- **ML Prediction Accuracy:** CLV MAE < 15%, Churn AUC > 0.8
- **API Uptime:** > 99.5%

---

## 11. Next Steps

### Immediate Implementation Priorities
1. **Backend scaffolding:** FastAPI project structure, database setup
2. **Authentication flow:** Shopify OAuth implementation
3. **Webhook ingestion:** Idempotent processing pipeline (ADR-003)
4. **Core domain models:** Orders, customers, products
5. **Basic analytics API:** Revenue and customer endpoints
6. **Frontend dashboard:** Authentication + first analytics view

### Phase 1 Milestones
- [ ] Shopify integration complete
- [ ] Webhook pipeline operational
- [ ] Basic revenue dashboard
- [ ] First ML model (CLV) deployed
- [ ] Weekly summary email automation
- [ ] Beta launch with 10 pilot stores

---

**Document Owner:** Ali Aghili  
**Project Status:** Architecture complete, ready for development sprint
