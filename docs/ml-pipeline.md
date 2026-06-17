# ML Pipeline Design

## Overview

RevenueOS uses a **batch ML pipeline** powered by **Celery** and **PostgreSQL** to generate predictive insights and anomaly detection for e-commerce stores.

The pipeline runs scheduled jobs daily to:
- Engineer features from raw transaction data
- Train and predict using scikit-learn, XGBoost, and Prophet models
- Generate natural-language insights via GPT-4o-mini
- Deliver insights to users via dashboard and email

---

## Architecture

```
┌─────────────────┐
│   PostgreSQL      │
│   (raw data)      │
│   orders          │
│   customers       │
│   products        │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  Celery Worker           │
│  (daily scheduled jobs)  │
│  Feature Engineering     │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  customer_features       │
│  (feature store)         │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Celery Worker           │
│  ML Models               │
│  • scikit-learn          │
│  • XGBoost               │
│  • Prophet               │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  insights table          │
│  (AI-generated insights) │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Frontend + Email        │
│  (user sees insights)    │
└─────────────────────────┘
```

---

## Feature Store

`customer_features` table — stores computed features per customer, updated daily.

| Column | Type | Description |
|---|---|---|
| `customer_id` | UUID | FK to customers |
| `recency_days` | INT | Days since last order |
| `frequency` | INT | Total number of orders |
| `monetary` | DECIMAL | Total spend (lifetime value proxy) |
| `avg_order_value` | DECIMAL | Average order value |
| `days_since_first_order` | INT | Customer tenure in days |
| `last_order_at` | TIMESTAMP | Timestamp of most recent order |
| `computed_at` | TIMESTAMP | Feature computation timestamp |

**Updated by:** `compute_customer_features()` Celery job (daily at 03:00 UTC)

---

## Models (MVP)

### 1. CLV Prediction

- **Algorithm:** `LinearRegression` (scikit-learn)
- **Features:** `recency_days`, `frequency`, `monetary`, `avg_order_value`, `days_since_first_order`
- **Target:** `total_spent` (proxy for future CLV)
- **Training:** Weekly retrain on customers with `frequency >= 2`, last 12 months of orders
- **Output:** `predicted_clv` stored in `customer_features`
- **Use case:** Identify high-value customers for retention campaigns

---

### 2. Churn Risk

#### Phase 1: Rule-Based

```python
if recency_days > 60 and frequency >= 2 and last_order_at < NOW() - INTERVAL '60 days':
    churn_risk_score = 0.8
```

**Output:** `churn_risk_score` (0–1) in `customer_features`

#### Phase 2: ML-Based

- **Algorithm:** `LogisticRegression` (scikit-learn)
- **Features:** `recency_days`, `frequency`, `monetary`, `avg_order_value`
- **Target:** `churned` (binary: 1 if no order in last 90 days)
- **Training:** Weekly retrain on customers with `frequency >= 2`
- **Use case:** Send win-back emails to high-risk churners

---

### 3. Anomaly Detection

#### Revenue Anomaly

```python
if daily_revenue > 1.2 * rolling_avg_7d:
    insight = "Revenue spike detected"
elif daily_revenue < 0.8 * rolling_avg_7d:
    insight = "Revenue drop detected"
```

**Data source:** `daily_metrics` table

#### Product Anomaly

```python
if product_orders_today > 2 * rolling_avg_7d:
    insight = f"Product {product_name} trending up"
```

**Use case:** Auto-generate insights for trending products or revenue dips

---

### 4. Product Association Rules

- **Algorithm:** Apriori (`mlxtend.frequent_patterns`)
- **Input:** `order_items` grouped by `order_id`
- **Parameters:** `min_support=0.01`, `min_confidence=0.3`
- **Output:** Rules of the form “Customers who bought X also bought Y”
- **Training:** Weekly on last 90 days of orders
- **Use case:** Cross-sell recommendations in dashboard

---

## Celery Jobs

### 1. `compute_daily_metrics()`
**Schedule:** Daily at 02:00 UTC

- Aggregate daily revenue by store
- Aggregate revenue by product, category, payment method, coupon
- Calculate daily active customers, new customers, repeat customers
- Store in `daily_metrics` table

### 2. `compute_customer_features()`
**Schedule:** Daily at 03:00 UTC

- For each customer: calculate RFM (recency, frequency, monetary), `avg_order_value`, `days_since_first_order`
- Upsert into `customer_features` table

### 3. `generate_insights()`
**Schedule:** Daily at 04:00 UTC

- Run anomaly detection (revenue, product)
- Run churn prediction
- Run CLV prediction
- Generate natural-language insights via GPT-4o-mini:

```
You are a revenue analyst. Given:
- Revenue today: $12,340
- 7-day avg: $10,200
- Top product: "Blue Sneakers" (120 orders, +40% vs last week)
- Churn risk customers: 23

Generate 3 actionable insights in plain English.
```

- Store insights in `insights` table with `type`, `severity`, `message`, `metadata`

### 4. `send_weekly_summary_emails()`
**Schedule:** Weekly on Monday at 06:00 UTC

- For each store: fetch weekly metrics (revenue, orders, customers) and top 5 insights from past 7 days
- Generate HTML email with revenue trend chart, top products, AI insights
- Send via SendGrid / Mailgun

---

## Training & Retraining Strategy

| Model | Training Frequency | Data Window | Trigger |
|---|---|---|---|
| CLV Prediction | Weekly | 12 months | Celery schedule |
| Churn Prediction | Weekly | 12 months | Celery schedule |
| Anomaly Detection | Real-time | 7 days | Daily job |
| Association Rules | Weekly | 90 days | Celery schedule |

**Versioning:**
- Models stored in `models/` directory with timestamp (e.g., `clv_model_2025_06_17.pkl`)
- Active model reference stored in `model_registry` table

---

## Feature Engineering

### RFM Features

**Recency:**
```sql
SELECT
    customer_id,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) / 86400 AS recency_days
FROM orders
GROUP BY customer_id;
```

**Frequency:**
```sql
SELECT
    customer_id,
    COUNT(*) AS frequency
FROM orders
GROUP BY customer_id;
```

**Monetary:**
```sql
SELECT
    customer_id,
    SUM(total_price) AS monetary
FROM orders
GROUP BY customer_id;
```

### Derived Features

```
avg_order_value          = monetary / frequency
days_since_first_order   = NOW() - MIN(created_at)
order_frequency_per_month = frequency / (days_since_first_order / 30)
```

---

## Model Monitoring

| Model | Metric | Threshold | Action |
|---|---|---|---|
| CLV | MAE | < $50 | Retrain if MAE > $75 |
| Churn | AUC-ROC | > 0.75 | Retrain if AUC < 0.70 |
| Anomaly | False positive rate | < 5% | Tune threshold if FPR > 10% |

### Prediction Logging

All predictions logged to `model_predictions` table:

| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `model_name` | VARCHAR | e.g., `clv_prediction` |
| `model_version` | VARCHAR | e.g., `2025_06_17` |
| `customer_id` | UUID | FK to customers |
| `prediction` | JSONB | Model output |
| `features` | JSONB | Input features used |
| `created_at` | TIMESTAMP | Prediction timestamp |

---

## Error Handling

| Failure | Strategy |
|---|---|
| Job failure | Retry 3× with exponential backoff (Celery) |
| Model load failure | Fall back to last known good model |
| Missing features | Skip customer and log warning |
| GPT-4o-mini timeout | Return generic insight template |
