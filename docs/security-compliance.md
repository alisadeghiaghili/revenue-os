# Security & Compliance

## Overview

RevenueOS processes sensitive merchant data (orders, customers, revenue). This document defines security controls, compliance requirements, and implementation guidelines.

---

## 1. Data Encryption

### At Rest

**Shopify Access Tokens:**
- **Requirement:** Encrypt `stores.shopify_access_token` before storing in PostgreSQL
- **Implementation:** Python `cryptography.fernet`
- **Key Management:** Store encryption key in environment variable `FERNET_KEY`

**`app/security/encryption.py`:**

```python
from cryptography.fernet import Fernet
import os

FERNET_KEY = os.getenv("FERNET_KEY")
if not FERNET_KEY:
    raise ValueError("FERNET_KEY environment variable not set")

cipher = Fernet(FERNET_KEY.encode())

def encrypt_token(token: str) -> str:
    """Encrypt Shopify access token before storing."""
    return cipher.encrypt(token.encode()).decode()

def decrypt_token(encrypted_token: str) -> str:
    """Decrypt Shopify access token when needed."""
    return cipher.decrypt(encrypted_token.encode()).decode()
```

**Database Schema:**

```sql
CREATE TABLE stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shopify_domain VARCHAR(255) NOT NULL UNIQUE,
    shopify_access_token TEXT NOT NULL,  -- encrypted with Fernet
    plan VARCHAR(50) DEFAULT 'starter',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Usage:**

```python
# When saving
store.shopify_access_token = encrypt_token(plaintext_token)
db.add(store)

# When retrieving
plaintext_token = decrypt_token(store.shopify_access_token)
```

---

### In Transit

- **HTTPS only:** Enforce TLS 1.2+ in production
- **HSTS:** Set `Strict-Transport-Security` header
- **Railway/Render:** Automatically provision TLS certificates

**`app/main.py`:**

```python
from fastapi import FastAPI
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

app = FastAPI()

if os.getenv("ENVIRONMENT") == "production":
    app.add_middleware(HTTPSRedirectMiddleware)
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=["api.revenueos.com", "*.revenueos.com"]
    )

@app.middleware("http")
async def add_security_headers(request, call_next):
    response = await call_next(request)
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    return response
```

---

## 2. Authentication & Authorization

### JWT Authentication

- **Algorithm:** HS256
- **Expiry:** 7 days
- **Refresh token:** stored in HTTP-only cookie
- **Access token:** returned in response body

**`app/security/jwt.py`:**

```python
from datetime import datetime, timedelta
import jwt
import os

JWT_SECRET = os.getenv("JWT_SECRET")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_DAYS = 7

def create_access_token(store_id: str, store_domain: str) -> str:
    payload = {
        "store_id": store_id,
        "store_domain": store_domain,
        "exp": datetime.utcnow() + timedelta(days=JWT_EXPIRY_DAYS),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def verify_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")
```

**`app/api/v1/auth.py`:**

```python
@router.post("/auth/shopify/callback")
async def shopify_callback(code: str, shop: str, response: Response):
    access_token = exchange_code_for_token(code, shop)
    store = create_or_update_store(shop, access_token)
    jwt_token = create_access_token(store.id, store.shopify_domain)

    response.set_cookie(
        key="refresh_token",
        value=jwt_token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=JWT_EXPIRY_DAYS * 24 * 60 * 60,
    )

    return {
        "access_token": jwt_token,
        "token_type": "bearer",
        "expires_in": JWT_EXPIRY_DAYS * 24 * 60 * 60,
    }
```

**`app/dependencies.py`:**

```python
async def get_current_store(authorization: str = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    token = authorization.split(" ")[1]
    payload = verify_token(token)
    return payload["store_id"]
```

---

## 3. Webhook Security

### Shopify HMAC Verification

**`app/security/webhooks.py`:**

```python
import hmac
import hashlib
import base64
import os
from fastapi import HTTPException, Request

SHOPIFY_WEBHOOK_SECRET = os.getenv("SHOPIFY_WEBHOOK_SECRET")

async def verify_shopify_webhook(request: Request):
    hmac_header = request.headers.get("X-Shopify-Hmac-SHA256")
    if not hmac_header:
        raise HTTPException(status_code=401, detail="Missing HMAC header")

    body = await request.body()
    computed_hmac = hmac.new(
        SHOPIFY_WEBHOOK_SECRET.encode(), body, hashlib.sha256
    ).digest()

    if not hmac.compare_digest(computed_hmac, base64.b64decode(hmac_header)):
        raise HTTPException(status_code=401, detail="Invalid HMAC signature")
```

**Usage:**

```python
@router.post("/webhooks/shopify/orders/created")
async def shopify_order_created(
    request: Request,
    _: None = Depends(verify_shopify_webhook)
):
    body = await request.json()
    # Process webhook...
```

### WooCommerce Webhook Signature

```python
WOOCOMMERCE_WEBHOOK_SECRET = os.getenv("WOOCOMMERCE_WEBHOOK_SECRET")

async def verify_woocommerce_webhook(request: Request):
    signature_header = request.headers.get("X-WC-Webhook-Signature")
    if not signature_header:
        raise HTTPException(status_code=401, detail="Missing signature header")

    body = await request.body()
    computed_signature = hmac.new(
        WOOCOMMERCE_WEBHOOK_SECRET.encode(), body, hashlib.sha256
    ).digest()

    if not hmac.compare_digest(computed_signature, base64.b64decode(signature_header)):
        raise HTTPException(status_code=401, detail="Invalid signature")
```

---

## 4. Multi-Tenancy Isolation

**EVERY database query MUST filter by `store_id`** to prevent cross-tenant data leakage.

**`app/repositories/base.py`:**

```python
class BaseRepository:
    def __init__(self, db: Session, store_id: str):
        self.db = db
        self.store_id = store_id

    def _enforce_tenant_filter(self, query):
        return query.filter_by(store_id=self.store_id)
```

**`app/repositories/order_repository.py`:**

```python
class OrderRepository(BaseRepository):
    def get_orders(self, limit: int = 100):
        return self._enforce_tenant_filter(
            self.db.query(Order)
        ).limit(limit).all()

    def get_order_by_id(self, order_id: str):
        order = self._enforce_tenant_filter(
            self.db.query(Order).filter(Order.id == order_id)
        ).first()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        return order
```

**Database-level enforcement:**

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    shopify_order_id VARCHAR(255) NOT NULL,
    CONSTRAINT unique_order_per_store UNIQUE (store_id, shopify_order_id)
);

CREATE INDEX idx_orders_store_id ON orders(store_id);
```

**Automated test:**

```python
def test_cross_tenant_access_blocked():
    store_a = create_test_store()
    store_b = create_test_store()
    order_a = create_test_order(store_a.id)

    repo = OrderRepository(db, store_b.id)

    with pytest.raises(HTTPException) as exc:
        repo.get_order_by_id(order_a.id)

    assert exc.value.status_code == 404
```

---

## 5. Rate Limiting

### Option 1: SlowAPI (Development)

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/metrics/revenue")
@limiter.limit("60/minute")
async def get_revenue_metrics(request: Request):
    ...
```

### Option 2: Cloudflare (Production — Recommended)

| Endpoint Group | Limit |
|---|---|
| Dashboard API | 100 req/min per authenticated user |
| Webhook endpoints | 1,000 req/min per IP |
| Public endpoints | 300 req/min per IP |

```
If Request URI Path matches /api/v1/* and Request Rate > 100/min
Then Block
```

---

## 6. GDPR Compliance

### Requirements
1. **Data Export:** User can download all their data
2. **Data Deletion:** User can request full account deletion
3. **Consent:** User must consent to data processing
4. **Retention:** Delete inactive accounts after 2 years

### Data Export

```python
@router.post("/gdpr/export")
async def export_user_data(
    background_tasks: BackgroundTasks,
    store_id: str = Depends(get_current_store),
    db: Session = Depends(get_db)
):
    service = GDPRService(db, store_id)
    background_tasks.add_task(service.generate_export)
    return {"message": "Export initiated. You will receive an email with download link."}
```

**`app/services/gdpr_service.py`:**

```python
class GDPRService:
    def generate_export(self):
        data = {
            "store": self._export_store(),
            "orders": self._export_orders(),
            "customers": self._export_customers(),
            "products": self._export_products(),
            "insights": self._export_insights(),
            "metrics": self._export_metrics(),
        }
        file_url = upload_to_r2(data, expires_in=86400)  # 24 hours
        send_email(
            to=self.get_store_email(),
            subject="Your RevenueOS Data Export",
            body=f"Download your data: {file_url}\nLink expires in 24 hours."
        )
```

### Data Deletion

```python
@router.post("/gdpr/delete")
async def delete_user_data(
    background_tasks: BackgroundTasks,
    store_id: str = Depends(get_current_store),
    db: Session = Depends(get_db)
):
    service = GDPRService(db, store_id)
    background_tasks.add_task(service.delete_all_data)
    return {"message": "Deletion initiated. All data will be permanently removed within 24 hours."}
```

```python
def delete_all_data(self):
    # Delete in dependency order
    for model in [Insight, CustomerFeature, DailyMetric, OrderItem, Order, Customer, Product, Store]:
        self.db.query(model).filter_by(store_id=self.store_id).delete()
    self.db.commit()
    log_gdpr_deletion(self.store_id)
```

### Consent Management

```sql
ALTER TABLE stores ADD COLUMN gdpr_consent_given BOOLEAN DEFAULT FALSE;
ALTER TABLE stores ADD COLUMN gdpr_consent_at TIMESTAMPTZ;
```

```python
@router.post("/auth/consent")
async def give_gdpr_consent(
    store_id: str = Depends(get_current_store),
    db: Session = Depends(get_db)
):
    store = db.query(Store).filter(Store.id == store_id).first()
    store.gdpr_consent_given = True
    store.gdpr_consent_at = datetime.utcnow()
    db.commit()
    return {"message": "Consent recorded"}
```

---

## 7. Secrets Management

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/revenueos

# Encryption
FERNET_KEY=<base64-encoded-32-byte-key>

# JWT
JWT_SECRET=<random-256-bit-secret>

# Shopify
SHOPIFY_CLIENT_ID=<shopify-app-client-id>
SHOPIFY_CLIENT_SECRET=<shopify-app-client-secret>
SHOPIFY_WEBHOOK_SECRET=<shopify-webhook-secret>

# WooCommerce
WOOCOMMERCE_WEBHOOK_SECRET=<woocommerce-webhook-secret>

# OpenAI
OPENAI_API_KEY=<openai-api-key>

# Email
SENDGRID_API_KEY=<sendgrid-api-key>

# Cloudflare R2
R2_ACCESS_KEY_ID=<r2-access-key>
R2_SECRET_ACCESS_KEY=<r2-secret-key>
R2_BUCKET_NAME=revenueos-exports
R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com

# Monitoring
SENTRY_DSN=<sentry-dsn>

# Environment
ENVIRONMENT=production
```

### Secret Rotation

- **Never commit `.env` files**
- Use Railway/Render environment variables
- Rotate secrets every **90 days**

```python
# scripts/rotate_jwt_secret.py
import secrets

def rotate_jwt_secret():
    new_secret = secrets.token_urlsafe(32)
    print(f"New JWT_SECRET: {new_secret}")
    print("Update in Railway/Render environment variables")
    print("Warning: All existing tokens will be invalidated")

if __name__ == "__main__":
    rotate_jwt_secret()
```

---

## 8. Audit Logging

Log all security-sensitive events: login attempts, GDPR requests, webhook verification failures, rate limit violations.

**`app/models/audit_log.py`:**

```python
class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(UUID, primary_key=True, server_default=text("gen_random_uuid()"))
    store_id = Column(UUID, nullable=True)  # nullable for failed auth attempts
    event_type = Column(String(100), nullable=False)
    user_agent = Column(Text)
    ip_address = Column(String(45))
    metadata = Column(JSONB)
    created_at = Column(TIMESTAMP, server_default=text("NOW()"))
```

**`app/services/audit_service.py`:**

```python
def log_audit_event(
    db: Session,
    event_type: str,
    store_id: str | None,
    ip_address: str,
    user_agent: str,
    metadata: dict = None
):
    log = AuditLog(
        store_id=store_id,
        event_type=event_type,
        ip_address=ip_address,
        user_agent=user_agent,
        metadata=metadata or {}
    )
    db.add(log)
    db.commit()
```

**Usage:**

```python
@router.post("/auth/login")
async def login(request: Request, db: Session = Depends(get_db)):
    try:
        # Auth logic...
        log_audit_event(db, "login_success", store.id,
                        request.client.host, request.headers.get("User-Agent"))
    except HTTPException:
        log_audit_event(db, "login_failed", None,
                        request.client.host, request.headers.get("User-Agent"))
        raise
```

---

## 9. Dependency Scanning

**`.github/workflows/security.yml`:**

```yaml
name: Security Scan

on:
  pull_request:
  push:
    branches: [main]

jobs:
  dependency-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install safety
          pip install -r requirements.txt

      - name: Run Safety check
        run: safety check --json

      - name: Run Bandit (static analysis)
        run: |
          pip install bandit
          bandit -r app/ -f json -o bandit-report.json
```

---

## 10. Incident Response Plan

### Incident Types

| Type | Example |
|---|---|
| Data Breach | Unauthorized access to customer data |
| Token Compromise | JWT or Shopify access token leaked |
| DDoS Attack | Overwhelming traffic |
| SQL Injection | Successful exploitation |

### Response Protocol

1. **Detect** — Monitor Sentry errors, Cloudflare traffic spikes, audit logs
2. **Contain** — Rotate compromised tokens, enable Cloudflare “I’m Under Attack” mode, disable affected endpoints
3. **Eradicate** — Patch vulnerability, deploy fix, run security scan
4. **Recover** — Re-enable services, monitor for 24 hours
5. **Post-Mortem** — Document incident, update controls, notify affected users if GDPR-required

**Security contact:** security@revenueos.com  
**Responsible disclosure:** `https://revenueos.com/.well-known/security.txt`

---

## Checklist

- [x] Shopify access tokens encrypted with Fernet
- [x] JWT auth with HS256, 7-day expiry, HTTP-only cookies
- [x] Webhook HMAC verification (Shopify + WooCommerce)
- [x] Multi-tenancy isolation enforced at repository layer
- [x] Rate limiting (SlowAPI + Cloudflare)
- [x] GDPR export/delete endpoints
- [x] HTTPS enforced in production
- [x] Secrets in Railway/Render environment variables
- [x] Audit logging for security events
- [x] Dependency scanning in CI
- [x] Incident response plan documented
