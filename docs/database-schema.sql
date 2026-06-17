-- RevenueOS Database Schema
-- Version: 1.0
-- Last Updated: 2026-06-17
-- 
-- Design Principles:
-- 1. Multi-tenancy: Every table has store_id for tenant isolation
-- 2. Idempotency: All webhook-driven inserts check idempotency_key
-- 3. Audit trail: created_at and updated_at on all tables
-- 4. Normalization: Separate order_items from orders for flexibility
-- 5. Indexing: Composite indexes on (store_id, frequently_queried_column)

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- STORES TABLE
-- ============================================================================
CREATE TABLE stores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform VARCHAR(50) NOT NULL CHECK (platform IN ('shopify', 'woocommerce')),
    shop_domain VARCHAR(255) NOT NULL UNIQUE, -- e.g., mystore.myshopify.com
    access_token TEXT NOT NULL, -- Encrypted API access token
    webhook_secret TEXT NOT NULL, -- For HMAC verification
    currency VARCHAR(3) DEFAULT 'USD',
    timezone VARCHAR(50) DEFAULT 'UTC',
    onboarded_at TIMESTAMP NOT NULL DEFAULT NOW(),
    subscription_status VARCHAR(20) DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'paused', 'cancelled')),
    subscription_plan VARCHAR(50), -- e.g., 'starter', 'growth', 'enterprise'
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stores_platform ON stores(platform);
CREATE INDEX idx_stores_subscription_status ON stores(subscription_status);

-- ============================================================================
-- CUSTOMERS TABLE
-- ============================================================================
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    external_id VARCHAR(255) NOT NULL, -- Shopify/WooCommerce customer ID
    email VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    total_spent DECIMAL(12, 2) DEFAULT 0,
    orders_count INTEGER DEFAULT 0,
    first_order_date TIMESTAMP,
    last_order_date TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(store_id, external_id)
);

CREATE INDEX idx_customers_store_id ON customers(store_id);
CREATE INDEX idx_customers_email ON customers(store_id, email);
CREATE INDEX idx_customers_total_spent ON customers(store_id, total_spent DESC);
CREATE INDEX idx_customers_last_order_date ON customers(store_id, last_order_date DESC);

-- ============================================================================
-- ORDERS TABLE
-- ============================================================================
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    external_id VARCHAR(255) NOT NULL, -- Shopify/WooCommerce order ID
    idempotency_key VARCHAR(255) NOT NULL, -- Webhook deduplication
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    order_number VARCHAR(100),
    order_date TIMESTAMP NOT NULL,
    status VARCHAR(50) NOT NULL, -- e.g., 'pending', 'completed', 'refunded'
    total_amount DECIMAL(12, 2) NOT NULL,
    subtotal_amount DECIMAL(12, 2),
    tax_amount DECIMAL(12, 2) DEFAULT 0,
    shipping_amount DECIMAL(12, 2) DEFAULT 0,
    discount_amount DECIMAL(12, 2) DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(100),
    coupon_code VARCHAR(100),
    channel VARCHAR(50), -- e.g., 'web', 'mobile', 'pos'
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(store_id, external_id),
    UNIQUE(store_id, idempotency_key)
);

CREATE INDEX idx_orders_store_id ON orders(store_id);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(store_id, order_date DESC);
CREATE INDEX idx_orders_status ON orders(store_id, status);
CREATE INDEX idx_orders_idempotency_key ON orders(store_id, idempotency_key);

-- ============================================================================
-- ORDER_ITEMS TABLE
-- ============================================================================
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    external_product_id VARCHAR(255), -- Shopify/WooCommerce product ID
    external_variant_id VARCHAR(255), -- For product variants
    product_name VARCHAR(500),
    variant_title VARCHAR(255),
    sku VARCHAR(255),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(12, 2) NOT NULL,
    total_price DECIMAL(12, 2) NOT NULL,
    category VARCHAR(255), -- Product category (if available)
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_store_id ON order_items(store_id);
CREATE INDEX idx_order_items_product ON order_items(store_id, external_product_id);
CREATE INDEX idx_order_items_category ON order_items(store_id, category);

-- ============================================================================
-- DAILY_METRICS TABLE
-- Pre-aggregated metrics for fast dashboard queries
-- ============================================================================
CREATE TABLE daily_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_revenue DECIMAL(12, 2) DEFAULT 0,
    total_orders INTEGER DEFAULT 0,
    new_customers INTEGER DEFAULT 0,
    returning_customers INTEGER DEFAULT 0,
    avg_order_value DECIMAL(10, 2) DEFAULT 0,
    total_items_sold INTEGER DEFAULT 0,
    total_discount DECIMAL(12, 2) DEFAULT 0,
    total_refunds DECIMAL(12, 2) DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(store_id, date)
);

CREATE INDEX idx_daily_metrics_store_date ON daily_metrics(store_id, date DESC);

-- ============================================================================
-- CUSTOMER_FEATURES TABLE
-- Pre-computed features for ML models
-- ============================================================================
CREATE TABLE customer_features (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Recency, Frequency, Monetary (RFM)
    recency_days INTEGER, -- Days since last purchase
    frequency INTEGER, -- Total number of orders
    monetary DECIMAL(12, 2), -- Total lifetime spend
    
    -- Behavioral features
    avg_order_value DECIMAL(10, 2),
    avg_days_between_orders DECIMAL(8, 2),
    favorite_category VARCHAR(255),
    favorite_payment_method VARCHAR(100),
    
    -- Derived metrics
    predicted_clv DECIMAL(12, 2), -- From ML model
    churn_probability DECIMAL(5, 4), -- From ML model (0-1)
    segment VARCHAR(50), -- e.g., 'high_value', 'at_risk', 'loyal'
    
    last_computed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(store_id, customer_id)
);

CREATE INDEX idx_customer_features_store_id ON customer_features(store_id);
CREATE INDEX idx_customer_features_segment ON customer_features(store_id, segment);
CREATE INDEX idx_customer_features_churn ON customer_features(store_id, churn_probability DESC);

-- ============================================================================
-- INSIGHTS TABLE
-- AI-generated insights and anomalies
-- ============================================================================
CREATE TABLE insights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    insight_type VARCHAR(50) NOT NULL, -- e.g., 'anomaly', 'opportunity', 'alert'
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical')),
    title VARCHAR(500) NOT NULL,
    description TEXT NOT NULL,
    metric_name VARCHAR(100), -- e.g., 'revenue', 'churn_rate'
    metric_value DECIMAL(12, 2),
    date_range_start DATE,
    date_range_end DATE,
    is_read BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_insights_store_id ON insights(store_id, created_at DESC);
CREATE INDEX idx_insights_type ON insights(store_id, insight_type);
CREATE INDEX idx_insights_unread ON insights(store_id, is_read) WHERE is_read = FALSE;

-- ============================================================================
-- WEBHOOKS_LOG TABLE
-- Audit trail for all incoming webhooks
-- ============================================================================
CREATE TABLE webhooks_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    store_id UUID REFERENCES stores(id) ON DELETE SET NULL,
    idempotency_key VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL, -- e.g., 'orders/create', 'orders/updated'
    payload JSONB NOT NULL, -- Full webhook payload
    signature_valid BOOLEAN NOT NULL,
    processed BOOLEAN DEFAULT FALSE,
    error_message TEXT,
    received_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhooks_log_store_id ON webhooks_log(store_id, received_at DESC);
CREATE INDEX idx_webhooks_log_idempotency ON webhooks_log(idempotency_key);

-- ============================================================================
-- TRIGGER: Update updated_at timestamp automatically
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_stores_updated_at BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_daily_metrics_updated_at BEFORE UPDATE ON daily_metrics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_customer_features_updated_at BEFORE UPDATE ON customer_features
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS: Convenience views for common queries
-- ============================================================================

-- Active stores with healthy data
CREATE VIEW active_stores_summary AS
SELECT 
    s.id,
    s.shop_domain,
    s.platform,
    s.subscription_status,
    COUNT(DISTINCT o.id) as total_orders,
    COUNT(DISTINCT c.id) as total_customers,
    SUM(o.total_amount) as total_revenue,
    MAX(o.order_date) as last_order_date
FROM stores s
LEFT JOIN orders o ON s.id = o.store_id
LEFT JOIN customers c ON s.id = c.store_id
WHERE s.subscription_status IN ('trial', 'active')
GROUP BY s.id, s.shop_domain, s.platform, s.subscription_status;

-- Customer 360 view
CREATE VIEW customer_360 AS
SELECT 
    c.id,
    c.store_id,
    c.email,
    c.first_name,
    c.last_name,
    c.total_spent,
    c.orders_count,
    c.first_order_date,
    c.last_order_date,
    cf.recency_days,
    cf.frequency,
    cf.monetary,
    cf.avg_order_value,
    cf.predicted_clv,
    cf.churn_probability,
    cf.segment
FROM customers c
LEFT JOIN customer_features cf ON c.id = cf.customer_id;

-- ============================================================================
-- SEED DATA (for development only)
-- ============================================================================
-- See scripts/seed.py for programmatic seed data generation

COMMENT ON TABLE stores IS 'Multi-tenant store configurations';
COMMENT ON TABLE customers IS 'Customer master records with aggregate stats';
COMMENT ON TABLE orders IS 'Order transactions with idempotency guarantee';
COMMENT ON TABLE order_items IS 'Line items for each order';
COMMENT ON TABLE daily_metrics IS 'Pre-aggregated daily KPIs for fast queries';
COMMENT ON TABLE customer_features IS 'ML feature store for customer-level predictions';
COMMENT ON TABLE insights IS 'AI-generated insights and anomalies';
COMMENT ON TABLE webhooks_log IS 'Audit trail for all incoming webhook events';
