-- ============================================================
-- ShopSphere: Customer Segmentation & Churn Analysis
-- Analysis date fixed at 2026-09-01 (the "today" this dataset is snapshotted to)
-- ============================================================

-- --------------------------------------------------------------
-- STEP 1: Build an RFM base table (Recency, Frequency, Monetary)
-- Recency  = days since the customer's last order
-- Frequency = total number of orders placed
-- Monetary  = total amount spent, all-time
-- --------------------------------------------------------------
CREATE VIEW customer_rfm AS
SELECT
    c.customer_id,
    c.customer_name,
    c.signup_date,
    CAST(julianday('2026-09-01') - julianday(MAX(o.order_date)) AS INTEGER) AS recency_days,
    COUNT(o.order_id) AS frequency,
    COALESCE(SUM(o.total_amount), 0) AS monetary
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.signup_date;


-- --------------------------------------------------------------
-- STEP 2: Segment every customer using CASE WHEN on RFM values
-- Segment rules (simple, explainable thresholds):
--   New         -> signed up in the last 30 days, 0-1 orders
--   High-Value  -> 3+ orders AND ordered within the last 30 days
--   At-Risk     -> ordered before, but nothing in the last 31-90 days
--   Churned     -> no order in 90+ days (or never ordered at all)
--   Regular     -> everyone else (occasional but still active-ish)
-- --------------------------------------------------------------
CREATE VIEW customer_segments AS
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    monetary,
    CASE
        WHEN frequency <= 1
             AND julianday('2026-09-01') - julianday(signup_date) <= 30
            THEN 'New'
        WHEN frequency >= 3 AND recency_days <= 30
            THEN 'High-Value'
        WHEN recency_days > 90 OR frequency = 0
            THEN 'Churned'
        WHEN recency_days BETWEEN 31 AND 90
            THEN 'At-Risk'
        ELSE 'Regular'
    END AS segment
FROM customer_rfm;


-- --------------------------------------------------------------
-- STEP 3: Segment summary — how many customers per segment,
-- and how much revenue each segment represents
-- --------------------------------------------------------------
SELECT
    segment,
    COUNT(*) AS num_customers,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_revenue_per_customer
FROM customer_segments
GROUP BY segment
ORDER BY total_revenue DESC;


-- --------------------------------------------------------------
-- STEP 4: Top 10 customers by lifetime spend
-- --------------------------------------------------------------
SELECT
    customer_name,
    segment,
    frequency AS total_orders,
    monetary AS total_spent
FROM customer_segments
ORDER BY monetary DESC
LIMIT 10;


-- --------------------------------------------------------------
-- STEP 5: Revenue by product category (which categories drive sales)
-- --------------------------------------------------------------
SELECT
    p.category,
    COUNT(o.order_id) AS num_orders,
    SUM(o.total_amount) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN products p ON p.product_id = o.product_id
GROUP BY p.category
ORDER BY total_revenue DESC;


-- --------------------------------------------------------------
-- STEP 6: Repeat purchase rate — what % of customers ordered more than once
-- (a core retention metric — ties directly into CRM/lifecycle thinking)
-- --------------------------------------------------------------
SELECT
    ROUND(100.0 * SUM(CASE WHEN frequency > 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_purchase_rate_pct,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN frequency > 1 THEN 1 ELSE 0 END) AS repeat_customers
FROM customer_rfm;


-- --------------------------------------------------------------
-- STEP 7: At-Risk customers worth a win-back campaign
-- (directly actionable list — this is what a CRM team would export)
-- --------------------------------------------------------------
SELECT
    customer_name,
    recency_days,
    frequency AS past_orders,
    monetary AS lifetime_spend
FROM customer_segments
WHERE segment = 'At-Risk'
ORDER BY monetary DESC;
