<div align="center">

# RevenueOS

### AI Revenue Intelligence Platform for E-commerce

**Predict. Detect. Act. Grow.**

[![Python 3.11+](https://img.shields.io/badge/Python-3.11+-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Next.js 14](https://img.shields.io/badge/Next.js-14-000000?style=flat-square&logo=next.js&logoColor=white)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![License: Proprietary](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)](./LICENSE)

[Overview](#-overview) · [Architecture](#-architecture) · [Quick Start](#-quick-start) · [Documentation](#-documentation) · [Roadmap](#-roadmap)

</div>

---

## 🎯 Overview

Store owners drown in data but lack actionable intelligence. RevenueOS is an AI-powered co-pilot for Shopify and WooCommerce merchants that turns raw transaction data into daily, automated revenue intelligence.

**Questions RevenueOS answers automatically:**

| Question | How |
|---|---|
| Why did revenue drop last week? | Anomaly detection with root-cause attribution |
| Which customers are about to churn? | XGBoost churn-probability scoring |
| What is the real CLV of my segments? | Regression model on historical order sequences |
| Which products drive retention vs. one-time purchases? | Cohort analysis + retention correlation |

**Current target:** MVP completion → **$10k MRR within 12 months**.

---

## 🏗️ Architecture

```
Shopify / WooCommerce
        │
        ▼
┌──────────────────┐     HMAC signature validation
│  Webhook Layer   │ ◄── Idempotency deduplication
│  (FastAPI)       │     Rate limiting (Redis, per-store)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   PostgreSQL     │  Primary store: orders, customers, products,
│   (primary DB)   │  daily_metrics, customer_features, insights
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Celery Workers  │  Async processing:
│  (Redis broker)  │  → Metric rollups (daily/weekly/monthly)
└────────┬─────────┘  → Feature engineering
         │             → ML inference
         ▼             → LLM insight generation
┌──────────────────┐
│   ML Pipeline    │  XGBoost CLV · XGBoost Churn
│                  │  Prophet anomaly · GPT-4o-mini insights
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   REST API       │  FastAPI · JWT auth · store_id isolation
│   (FastAPI)      │  Auto OpenAPI docs at /docs
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Frontend       │  Next.js 14 · shadcn/ui · Recharts
└──────────────────┘
```

> Full details in [`docs/architecture.md`](./docs/architecture.md).

### Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Next.js 14, Tailwind CSS, shadcn/ui, Recharts |
| **Backend API** | FastAPI, Python 3.11, Pydantic v2, Alembic |
| **Database** | PostgreSQL 16 (async via asyncpg + SQLAlchemy) |
| **Queue / Cache** | Redis 7, Celery 5 |
| **ML** | scikit-learn, XGBoost, Prophet, GPT-4o-mini |
| **Infrastructure** | Docker, Docker Compose, AWS / Railway |

### Multi-Tenancy

Every database table carries a `store_id` column. Every query — without exception — filters by `store_id`. The FastAPI dependency `get_store_id()` enforces this at the HTTP boundary via the `X-Store-ID` header. See [`docs/multi-tenancy.md`](./docs/multi-tenancy.md).

---

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 18+
- Python 3.11+

### 1. Clone and configure

```bash
git clone https://github.com/alisadeghiaghili/revenue-os.git
cd revenue-os
cp .env.example .env
# Edit .env — fill in DATABASE_URL, REDIS_URL, SECRET_KEY, and platform API keys
```

### 2. Start services

```bash
docker-compose up -d
```

This starts PostgreSQL, Redis, and (optionally) a local Celery worker container.

### 3. Backend setup

```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head            # Run all DB migrations
uvicorn main:app --reload       # Starts at http://localhost:8000
```

API docs are available at `http://localhost:8000/docs`.

### 4. Frontend setup

```bash
cd frontend
npm install
npm run dev                     # Starts at http://localhost:3000
```

### 5. Celery worker (separate terminal)

```bash
cd backend
source venv/bin/activate
celery -A app.workers.celery_app worker --loglevel=info
```

---

## 🗂️ Project Structure

```
revenue-os/
├── backend/
│   ├── main.py                   # FastAPI app entry point
│   ├── requirements.txt
│   ├── alembic.ini
│   ├── alembic/                  # DB migration scripts
│   └── app/
│       ├── api/                  # HTTP route handlers (no business logic)
│       ├── services/             # Business logic layer
│       ├── repositories/         # SQLAlchemy data access layer
│       ├── models/               # ORM models
│       ├── schemas/              # Pydantic request/response schemas
│       ├── workers/              # Celery tasks (celery_app.py + tasks.py)
│       ├── db/                   # Async engine, session factory, base
│       └── core/                 # Config, logging, exceptions, dependencies
├── frontend/
│   ├── app/                      # Next.js app router
│   ├── components/               # shadcn/ui + custom components
│   └── lib/                      # API client, hooks, utilities
├── docs/
│   ├── architecture.md
│   ├── database-schema.md
│   ├── api-spec.md
│   ├── multi-tenancy.md
│   ├── deployment.md
│   └── decisions/                # Architecture Decision Records (ADRs)
│       ├── 001-why-fastapi.md
│       ├── 002-why-postgresql.md
│       ├── 003-webhook-idempotency.md
│       └── 004-ml-stack.md
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 📚 Documentation

| Document | Description |
|---|---|
| [`docs/architecture.md`](./docs/architecture.md) | System components, data flow, scaling phases |
| [`docs/database-schema.md`](./docs/database-schema.md) | Table definitions, indexes, relationships |
| [`docs/api-spec.md`](./docs/api-spec.md) | Endpoint reference (also auto-generated at `/docs`) |
| [`docs/multi-tenancy.md`](./docs/multi-tenancy.md) | Tenant isolation strategy and enforcement |
| [`docs/deployment.md`](./docs/deployment.md) | Railway / AWS deployment guide |
| [`docs/decisions/`](./docs/decisions/) | Architecture Decision Records (ADRs) |

---

## 🧪 Testing

```bash
# Backend — unit + integration tests
cd backend
pytest

# Backend — with coverage report
pytest --cov=app --cov-report=term-missing

# Frontend
cd frontend
npm test
```

Tests mirror the `app/` structure under `tests/`:

```
tests/
├── conftest.py          # Shared fixtures (AsyncClient, test DB session)
├── api/                 # Route handler tests
├── services/            # Business logic tests
└── repositories/        # Data access tests
```

---

## 🛡️ Security

| Area | Implementation |
|---|---|
| **Webhook verification** | HMAC signature validation on all incoming Shopify/WooCommerce events |
| **Authentication** | JWT tokens scoped to individual stores |
| **Tenant isolation** | `store_id` filter enforced at HTTP boundary and on every DB query |
| **SQL injection** | All queries use parameterized statements via SQLAlchemy ORM |
| **Rate limiting** | Redis-based per-store limits on API and webhook ingestion |
| **Secrets** | All keys and credentials in `.env` — never committed to version control |
| **Input sanitization** | Pydantic v2 validation on all request bodies and query params |

---

## 📦 Deployment

Full guide in [`docs/deployment.md`](./docs/deployment.md).

### Scaling roadmap

| Phase | Stores | Infrastructure |
|---|---|---|
| **MVP** | < 100 | Single PostgreSQL, single Redis, 2–4 Celery workers, Railway / Render |
| **Growth** | 100 – 1 000 | Read replicas, Redis cluster, horizontal Celery scaling, CDN |
| **Scale** | > 1 000 | Sharded PostgreSQL, dedicated ML inference service, Kafka / Redis Streams, multi-region |

---

## 🔭 Roadmap

- [x] Backend scaffold (FastAPI, PostgreSQL, Redis, Celery)
- [ ] Shopify webhook integration + HMAC verification
- [ ] WooCommerce webhook integration
- [ ] Daily metric aggregation pipeline
- [ ] CLV prediction model (XGBoost)
- [ ] Churn scoring model (XGBoost)
- [ ] Revenue anomaly detection (Prophet)
- [ ] LLM insight generation (GPT-4o-mini)
- [ ] Frontend dashboard (Next.js 14)
- [ ] Billing & subscription management

---

## 🧭 Development Workflow

```
feature/* or fix/* branches  →  PR to develop
develop                       →  auto-deploy to staging
main                          →  manual deploy to production
```

All PRs require passing tests before merge. Commit messages follow the format:

```
<type>: <short description>

Types: feat | fix | refactor | chore | docs | test | scaffold
```

---

## 📄 License

Proprietary — All Rights Reserved. See [LICENSE](./LICENSE).
