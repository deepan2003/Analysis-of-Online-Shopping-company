-- ============================================================
-- 50_views_for_bi.sql
-- Dashboard-ready views. Power BI (or any BI tool) should read
-- these views instead of re-implementing the logic.
--
-- Naming: vw_<subject>
-- ============================================================

USE ecommerce_analytics;

-- ------------------------------------------------------------
-- 1. Order fact table (one row per valid order, revenue de-duplicated)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_order_facts AS
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,
    DATE(o.order_purchase_timestamp)               AS purchase_date,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
    o.order_status,
    pay.order_revenue,
    COALESCE(it.item_count, 0)                     AS item_count,
    COALESCE(it.freight_value, 0)                  AS freight_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN (
    -- one row per order: payments are 1..n rows and must be summed first
    SELECT order_id, SUM(payment_value) AS order_revenue
    FROM order_payments
    GROUP BY order_id
) pay ON pay.order_id = o.order_id
LEFT JOIN (
    SELECT order_id,
           COUNT(*)               AS item_count,
           SUM(freight_value)     AS freight_value
    FROM order_items
    GROUP BY order_id
) it ON it.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
  AND o.order_purchase_timestamp IS NOT NULL;

-- ------------------------------------------------------------
-- 2. Monthly revenue with MoM / YoY growth
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT
    purchase_month,
    COUNT(*)                       AS orders_count,
    ROUND(SUM(order_revenue), 2)   AS revenue,
    ROUND(AVG(order_revenue), 2)   AS avg_order_value,
    SUM(SUM(order_revenue)) OVER (ORDER BY purchase_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_revenue,
    LAG(SUM(order_revenue)) OVER (ORDER BY purchase_month) AS prev_month_revenue,
    ROUND(
        (SUM(order_revenue) - LAG(SUM(order_revenue)) OVER (ORDER BY purchase_month))
        / NULLIF(LAG(SUM(order_revenue)) OVER (ORDER BY purchase_month), 0) * 100
    , 2) AS mom_growth_pct,
    ROUND(SUM(order_revenue) / NULLIF(SUM(SUM(order_revenue)) OVER (), 0) * 100, 2)
        AS pct_of_total_revenue
FROM vw_order_facts
GROUP BY purchase_month;

-- ------------------------------------------------------------
-- 3. RFM per customer (one row per real person)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_rfm AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_bucket AS m_score,
    CONCAT(r_score, f_score, m_bucket) AS rfm_score,
    ROUND((r_score + f_score + m_bucket) / 3, 2) AS rfm_avg,
    CASE
        WHEN r_score >= 4 AND f_score >= 4                THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score = 3                 THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score = 2                 THEN 'Promising'
        WHEN r_score >= 4 AND f_score = 1                 THEN 'New Customers'
        WHEN r_score = 3 AND f_score = 1                  THEN 'Cooling Off'
        WHEN r_score <= 2 AND f_score >= 3 AND m_bucket >= 4 THEN 'Cannot Lose Them'
        WHEN r_score <= 2 AND f_score >= 3                THEN 'At Risk'
        WHEN r_score <= 2 AND m_bucket >= 4               THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_bucket <= 2 THEN 'Hibernating'
        ELSE 'Others'
    END AS rfm_segment,
    last_order_at,
    first_order_at
FROM (
    SELECT
        x.*,
        CASE WHEN recency_days <= 30  THEN 5
             WHEN recency_days <= 90  THEN 4
             WHEN recency_days <= 180 THEN 3
             WHEN recency_days <= 365 THEN 2
             ELSE 1 END AS r_score,
        CASE WHEN frequency >= 5 THEN 5
             WHEN frequency = 4  THEN 4
             WHEN frequency = 3  THEN 3
             WHEN frequency = 2  THEN 2
             ELSE 1 END AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_bucket
    FROM (
        SELECT
            f.customer_unique_id,
            DATEDIFF(
                DATE_ADD((SELECT MAX(purchase_date) FROM vw_order_facts), INTERVAL 1 DAY),
                MAX(f.purchase_date)
            ) AS recency_days,
            COUNT(*)            AS frequency,
            SUM(f.order_revenue) AS monetary,
            MIN(f.purchase_date) AS first_order_at,
            MAX(f.purchase_date) AS last_order_at
        FROM vw_order_facts f
        GROUP BY f.customer_unique_id
    ) x
) s;

-- ------------------------------------------------------------
-- 4. RFM segment summary
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_rfm_segment_summary AS
SELECT
    rfm_segment,
    COUNT(*)                                    AS customers,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2)      AS pct_of_customers,
    ROUND(SUM(monetary), 2)                     AS total_revenue,
    ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 2) AS pct_of_revenue,
    ROUND(AVG(monetary), 2)                     AS avg_customer_value,
    ROUND(AVG(frequency), 2)                    AS avg_orders,
    ROUND(AVG(recency_days), 1)                 AS avg_days_since_last_order
FROM vw_customer_rfm
GROUP BY rfm_segment;

-- ------------------------------------------------------------
-- 5. Cohort retention matrix
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_cohort_retention AS
SELECT
    b.cohort_month,
    s.cohort_customers,
    b.month_index,
    COUNT(DISTINCT b.customer_unique_id) AS active_customers,
    ROUND(COUNT(DISTINCT b.customer_unique_id) / s.cohort_customers * 100, 2) AS retention_pct
FROM customer_cohort_base b
JOIN (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM customer_cohort_base
    GROUP BY cohort_month
) s ON s.cohort_month = b.cohort_month
WHERE b.month_index BETWEEN 0 AND 6
  AND s.cohort_customers >= 50
GROUP BY b.cohort_month, s.cohort_customers, b.month_index;

-- ------------------------------------------------------------
-- 6. Delivery fact (one row per delivered order)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_delivery_facts AS
SELECT
    o.order_id,
    c.customer_state,
    c.customer_city,
    o.order_purchase_timestamp,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp) AS estimated_days,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS delay_days,
    CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS is_on_time
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;

-- ------------------------------------------------------------
-- 7. Delivery KPI by state
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_delivery_by_state AS
SELECT
    customer_state,
    COUNT(*)                                   AS delivered_orders,
    ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
    ROUND(AVG(estimated_days), 1)              AS avg_estimated_days,
    ROUND(AVG(delay_days), 2)                  AS avg_delay_days,
    ROUND(SUM(is_on_time) / COUNT(*) * 100, 2) AS on_time_pct,
    ROUND((COUNT(*) - SUM(is_on_time)) / COUNT(*) * 100, 2) AS late_pct,
    COUNT(*) - SUM(is_on_time)                 AS late_orders
FROM vw_delivery_facts
GROUP BY customer_state;

-- ------------------------------------------------------------
-- 8. Monthly delivery performance
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_delivery_monthly AS
SELECT
    purchase_month,
    COUNT(*)                                   AS delivered_orders,
    ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
    ROUND(SUM(is_on_time) / COUNT(*) * 100, 2) AS on_time_pct
FROM vw_delivery_facts
GROUP BY purchase_month;

-- ------------------------------------------------------------
-- 9. Geo lookup for map visuals (one point per zip prefix)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_geo_zip AS
SELECT
    geolocation_zip_code_prefix AS zip_prefix,
    AVG(geolocation_lat)        AS lat,
    AVG(geolocation_lng)        AS lng,
    MAX(geolocation_state)      AS state
FROM geolocation
GROUP BY geolocation_zip_code_prefix;
