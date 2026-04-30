-- =========================================
-- PROJECT: E-commerce Customer Analytics
-- =========================================



-- =========================================
-- KPI SUMMARY 
-- =========================================

WITH 

-- Total Customers
customer_count AS (
    SELECT COUNT(DISTINCT customer_unique_id) AS total_customers
    FROM customers
),

-- Total Orders
order_count AS (
    SELECT COUNT(DISTINCT order_id) AS total_orders
    FROM orders
),

-- Total Revenue
revenue AS (
    SELECT SUM(payment_value) AS total_revenue
    FROM payments
),

-- Orders per customer 
customer_orders AS (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM customers c
    JOIN orders o 
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),

-- Repeat Customer Rate
repeat_rate AS (
    SELECT 
        ROUND(
            COUNT(CASE WHEN total_orders > 1 THEN 1 END) * 1.0
            / COUNT(*) * 100, 2
        ) AS repeat_customer_rate
    FROM customer_orders
)

SELECT 
    c.total_customers,
    o.total_orders,
    ROUND(r.total_revenue, 0) AS total_revenue,
    ROUND(r.total_revenue * 1.0 / o.total_orders, 2) AS avg_order_value,
    rr.repeat_customer_rate

FROM customer_count c
CROSS JOIN order_count o
CROSS JOIN revenue r
CROSS JOIN repeat_rate rr;


-- =========================
-- Monthly Revenue
-- =========================

SELECT 
    strftime('%Y-%m', o.order_purchase_timestamp) AS month,
    SUM(p.payment_value) AS revenue
FROM orders o
JOIN payments p 
    ON o.order_id = p.order_id
GROUP BY month
ORDER BY month;

-- =========================================
-- Top 10 Customers by Revenue
-- =========================================

SELECT 
    c.customer_unique_id,
    SUM(p.payment_value) AS total_spent
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
JOIN payments p 
    ON o.order_id = p.order_id
GROUP BY c.customer_unique_id
ORDER BY total_spent DESC
LIMIT 10;


-- =========================================
-- CUSTOMER RFM SEGMENTATION 
-- =========================================

WITH rfm_base AS (
    SELECT 
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_purchase_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value) AS monetary
    FROM customers c
    JOIN orders o 
        ON c.customer_id = o.customer_id
    JOIN payments p 
        ON o.order_id = p.order_id
    GROUP BY c.customer_unique_id
),

rfm_calc AS (
    SELECT *,
        CAST(
            julianday((SELECT MAX(order_purchase_timestamp) FROM orders)) 
            - julianday(last_purchase_date)
        AS INTEGER) AS recency
    FROM rfm_base
),

rfm_score AS (
    SELECT *,
        
        NTILE(5) OVER (ORDER BY recency DESC) AS recency_score, 
        NTILE(5) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary) AS monetary_score
    FROM rfm_calc
)

SELECT 
    customer_unique_id,
    monetary,
    frequency,
    recency,

    recency_score,
    frequency_score,
    monetary_score,

    recency_score || frequency_score || monetary_score AS rfm_score,

    CASE 
        WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'VIP'
        WHEN recency_score >= 3 AND frequency_score >= 3 THEN 'Loyal'
        WHEN recency_score >= 3 THEN 'Potential'
        ELSE 'At Risk'
    END AS segment

FROM rfm_score
ORDER BY monetary DESC;

-- =========================================
-- COHORT ANALYSIS (MONTHLY RETENTION)
-- =========================================

WITH cohort AS (
    -- Her müşterinin ilk sipariş ayı
    SELECT 
        c.customer_unique_id,
        STRFTIME('%Y-%m', MIN(o.order_purchase_timestamp)) AS cohort_month
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),

customer_orders AS (
    -- Tüm siparişler (ay bazında)
    SELECT 
        c.customer_unique_id,
        STRFTIME('%Y-%m', o.order_purchase_timestamp) AS order_month
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
),

cohort_data AS (
    -- Cohort ile siparişleri birleştir
    SELECT 
        co.cohort_month,
        co.customer_unique_id,
        coo.order_month,

        -- Kaçıncı ayda?
        (
            CAST(SUBSTR(coo.order_month,1,4) AS INTEGER) - 
            CAST(SUBSTR(co.cohort_month,1,4) AS INTEGER)
        ) * 12 +
        (
            CAST(SUBSTR(coo.order_month,6,2) AS INTEGER) - 
            CAST(SUBSTR(co.cohort_month,6,2) AS INTEGER)
        ) AS month_index

    FROM cohort co
    JOIN customer_orders coo
        ON co.customer_unique_id = coo.customer_unique_id
)

SELECT 
    cohort_month,
    month_index,
    COUNT(DISTINCT customer_unique_id) AS customers
FROM cohort_data
GROUP BY cohort_month, month_index
ORDER BY cohort_month, month_index;