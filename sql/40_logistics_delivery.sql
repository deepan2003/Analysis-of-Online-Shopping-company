-- ============================================================
-- 40_logistics_delivery.sql
-- Business question: Are packages arriving on time, and which
-- regions are facing delays?
--
-- Definitions (delivered orders only):
--   delivery_days      = days from purchase to customer delivery
--   estimated_days     = days from purchase to the estimated date
--   delay_days         = delivered_customer_date - estimated_delivery_date
--                        (positive = late, negative = early)
--   on_time            = delivered_customer_date <= estimated_delivery_date
-- ============================================================

USE ecommerce_analytics;

-- ------------------------------------------------------------
-- A. Order-level delivery fact table (feeds the map + gauge)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS order_delivery_fact;
CREATE TABLE order_delivery_fact AS
SELECT
    o.order_id,
    c.customer_state,
    c.customer_city,
    c.customer_zip_code_prefix,
    DATE(o.order_purchase_timestamp)                        AS purchase_date,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')        AS purchase_month,
    o.order_status,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)      AS delivery_days,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp)      AS estimated_days,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS delay_days,
    CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
         THEN 1 ELSE 0 END                                  AS is_on_time,
    CASE WHEN o.order_delivered_customer_date >  o.order_estimated_delivery_date
         THEN 1 ELSE 0 END                                  AS is_late
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;

ALTER TABLE order_delivery_fact
  ADD PRIMARY KEY (order_id),
  ADD KEY idx_state (customer_state),
  ADD KEY idx_month (purchase_month);

-- ------------------------------------------------------------
-- B. Gauge data: actual vs estimated delivery, company-wide
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                     AS delivered_orders,
    ROUND(AVG(delivery_days), 2)                                 AS avg_actual_delivery_days,
    ROUND(AVG(estimated_days), 2)                                AS avg_estimated_delivery_days,
    ROUND(AVG(delay_days), 2)                                    AS avg_delay_days,
    ROUND(SUM(is_on_time) / COUNT(*) * 100, 2)                   AS on_time_pct,
    ROUND(SUM(is_late)    / COUNT(*) * 100, 2)                   AS late_pct,
    SUM(is_late)                                                 AS late_orders,
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 2)     AS avg_days_late_when_late
FROM order_delivery_fact;

-- ------------------------------------------------------------
-- C. Delivery performance by state (map visual, worst first)
-- ------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*)                                                  AS delivered_orders,
    ROUND(AVG(delivery_days), 1)                              AS avg_delivery_days,
    ROUND(AVG(estimated_days), 1)                             AS avg_estimated_days,
    ROUND(AVG(delay_days), 2)                                 AS avg_delay_days,
    ROUND(SUM(is_on_time) / COUNT(*) * 100, 2)                AS on_time_pct,
    ROUND(SUM(is_late) / COUNT(*) * 100, 2)                   AS late_pct,
    SUM(is_late)                                              AS late_orders,
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 1)  AS avg_days_late_when_late
FROM order_delivery_fact
GROUP BY customer_state
HAVING COUNT(*) >= 30
ORDER BY late_pct DESC, delivered_orders DESC;

-- ------------------------------------------------------------
-- D. Monthly on-time trend (line chart next to the gauge)
-- ------------------------------------------------------------
SELECT
    purchase_month,
    COUNT(*)                                AS delivered_orders,
    ROUND(AVG(delivery_days), 1)            AS avg_delivery_days,
    ROUND(SUM(is_on_time) / COUNT(*) * 100, 2) AS on_time_pct,
    ROUND(SUM(is_late) / COUNT(*) * 100, 2)    AS late_pct
FROM order_delivery_fact
GROUP BY purchase_month
ORDER BY purchase_month;

-- ------------------------------------------------------------
-- E. Worst lanes: state pairs with the highest late rate
--    (seller state -> customer state), 30+ orders only
-- ------------------------------------------------------------
SELECT
    s.seller_state,
    d.customer_state,
    COUNT(*)                              AS orders_count,
    ROUND(AVG(d.delivery_days), 1)        AS avg_delivery_days,
    ROUND(SUM(d.is_late) / COUNT(*) * 100, 2) AS late_pct
FROM order_delivery_fact d
JOIN order_items i ON i.order_id = d.order_id
JOIN sellers s     ON s.seller_id = i.seller_id
GROUP BY s.seller_state, d.customer_state
HAVING COUNT(*) >= 30
ORDER BY late_pct DESC
LIMIT 20;
