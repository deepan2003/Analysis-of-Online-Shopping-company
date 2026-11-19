-- ============================================================
-- 20_rfm_segmentation.sql
-- Business question: Who are our best, high-spending buyers?
--
-- Grain: one row per real person (customer_unique_id).
--         customer_id is per-order, so it MUST NOT be used for RFM.
--
-- Recency   = days between the customer's last order and the
--             reference date (one day after the last order in the data).
-- Frequency = number of distinct valid orders.
-- Monetary  = total payment value across those orders.
--
-- Scoring (1 = worst, 5 = best):
--   R: <=30d = 5, <=90d = 4, <=180d = 3, <=365d = 2, else 1
--   F: 1 order = 1, 2 = 2, 3 = 3, 4 = 4, 5+ = 5
--   M: spend quintiles via NTILE(5) (continuous values, no tie problem)
--
-- Fixed R/F thresholds are used instead of NTILE because ~97% of
-- Olist customers ordered exactly once; NTILE would hand out high
-- frequency scores to one-time buyers purely to fill the buckets.
-- ============================================================

USE ecommerce_analytics;

-- ------------------------------------------------------------
-- A. Raw values + scores + segment (one row per customer)
-- ------------------------------------------------------------
WITH customer_orders AS (        -- one row per order, revenue de-duplicated
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        SUM(p.payment_value) AS order_value
    FROM orders o
    JOIN customers c      ON c.customer_id = o.customer_id
    JOIN order_payments p ON p.order_id    = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),
rfm_raw AS (
    SELECT
        co.customer_unique_id,
        DATEDIFF(
            DATE_ADD((SELECT MAX(DATE(order_purchase_timestamp)) FROM orders), INTERVAL 1 DAY),
            MAX(co.order_purchase_timestamp)
        )                                                        AS recency_days,
        COUNT(DISTINCT co.order_id)                              AS frequency,
        SUM(co.order_value)                                      AS monetary
    FROM customer_orders co
    GROUP BY co.customer_unique_id
),
rfm_scored AS (
    SELECT
        r.*,
        CASE WHEN recency_days <= 30  THEN 5
             WHEN recency_days <= 90  THEN 4
             WHEN recency_days <= 180 THEN 3
             WHEN recency_days <= 365 THEN 2
             ELSE 1 END                                          AS r_score,
        CASE WHEN frequency >= 5 THEN 5
             WHEN frequency = 4  THEN 4
             WHEN frequency = 3  THEN 3
             WHEN frequency = 2  THEN 2
             ELSE 1 END                                          AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)                    AS m_bucket
    FROM rfm_raw r
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary, 2)                    AS monetary,
    r_score, f_score, m_bucket AS m_score,
    CONCAT(r_score, f_score, m_bucket)    AS rfm_score,
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
    END AS rfm_segment
FROM rfm_scored
ORDER BY monetary DESC;

-- ------------------------------------------------------------
-- B. Segment summary (Power BI bar chart + revenue mix)
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT c.customer_unique_id, o.order_id, o.order_purchase_timestamp,
           SUM(p.payment_value) AS order_value
    FROM orders o
    JOIN customers c      ON c.customer_id = o.customer_id
    JOIN order_payments p ON p.order_id    = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),
rfm_raw AS (
    SELECT customer_unique_id,
           DATEDIFF(DATE_ADD((SELECT MAX(DATE(order_purchase_timestamp)) FROM orders), INTERVAL 1 DAY),
                    MAX(order_purchase_timestamp)) AS recency_days,
           COUNT(DISTINCT order_id) AS frequency,
           SUM(order_value)         AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    SELECT r.*,
           CASE WHEN recency_days <= 30 THEN 5 WHEN recency_days <= 90 THEN 4
                WHEN recency_days <= 180 THEN 3 WHEN recency_days <= 365 THEN 2 ELSE 1 END AS r_score,
           CASE WHEN frequency >= 5 THEN 5 WHEN frequency = 4 THEN 4
                WHEN frequency = 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC) AS m_bucket
    FROM rfm_raw r
),
segmented AS (
    SELECT r.*, CASE
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
        ELSE 'Others' END AS rfm_segment
    FROM rfm_scored r
)
SELECT
    rfm_segment,
    COUNT(*)                                          AS customers,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2)  AS pct_of_customers,
    ROUND(SUM(monetary), 2)                           AS total_revenue,
    ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 2) AS pct_of_revenue,
    ROUND(AVG(monetary), 2)                           AS avg_customer_value,
    ROUND(AVG(frequency), 2)                          AS avg_orders,
    ROUND(AVG(recency_days), 1)                       AS avg_days_since_last_order
FROM segmented
GROUP BY rfm_segment
ORDER BY total_revenue DESC;

-- ------------------------------------------------------------
-- C. Action list: valuable customers who have gone quiet
--    ("send a win-back coupon" audience, 90+ days inactive)
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT c.customer_unique_id, o.order_id, o.order_purchase_timestamp,
           SUM(p.payment_value) AS order_value
    FROM orders o
    JOIN customers c      ON c.customer_id = o.customer_id
    JOIN order_payments p ON p.order_id    = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
)
SELECT
    customer_unique_id,
    MAX(order_purchase_timestamp)                                   AS last_order_at,
    COUNT(DISTINCT order_id)                                        AS orders_count,
    ROUND(SUM(order_value), 2)                                      AS lifetime_value,
    DATEDIFF(DATE_ADD((SELECT MAX(DATE(order_purchase_timestamp)) FROM orders), INTERVAL 1 DAY),
             MAX(order_purchase_timestamp))                         AS days_inactive
FROM customer_orders
GROUP BY customer_unique_id
HAVING days_inactive >= 90
   AND SUM(order_value) >= 500
ORDER BY lifetime_value DESC
LIMIT 500;
