-- ============================================================
-- 10_revenue_by_month.sql
-- Business question: Are monthly sales growing or dropping?
--
-- Definitions
--   Revenue      = SUM(order_payments.payment_value) for VALID orders
--                  (canceled / unavailable orders are excluded).
--   AOV          = revenue / orders placed in that month.
--   MoM growth   = (this month - previous month) / previous month.
--   YoY growth   = (this month - same month last year) / same month last year.
--
-- Important: payments is 1..n rows per order, so it is aggregated to
-- one row per order BEFORE joining anything else. Joining orders,
-- payments and items directly would multiply the amounts.
-- ============================================================

USE ecommerce_analytics;

-- ------------------------------------------------------------
-- A. Monthly revenue + MoM / YoY growth (window functions)
-- ------------------------------------------------------------
WITH order_revenue AS (
    SELECT
        o.order_id,
        o.order_purchase_timestamp,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(p.payment_value)                              AS order_value
    FROM orders o
    JOIN order_payments p ON p.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY o.order_id, o.order_purchase_timestamp
),
monthly AS (
    SELECT
        order_month,
        COUNT(*)          AS orders_count,
        COUNT(DISTINCT order_id) AS distinct_orders,
        ROUND(SUM(order_value), 2) AS revenue,
        ROUND(AVG(order_value), 2) AS aov
    FROM order_revenue
    GROUP BY order_month
)
SELECT
    order_month,
    orders_count,
    revenue,
    aov,
    LAG(revenue) OVER (ORDER BY order_month)                       AS prev_month_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY order_month))
        / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0) * 100
    , 2)                                                           AS mom_growth_pct,
    LAG(revenue, 12) OVER (ORDER BY order_month)                   AS same_month_last_year,
    ROUND(
        (revenue - LAG(revenue, 12) OVER (ORDER BY order_month))
        / NULLIF(LAG(revenue, 12) OVER (ORDER BY order_month), 0) * 100
    , 2)                                                           AS yoy_growth_pct,
    SUM(revenue) OVER (ORDER BY order_month
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue,
    ROUND(
        revenue / NULLIF(SUM(revenue) OVER (), 0) * 100
    , 2)                                                           AS pct_of_total_revenue
FROM monthly
ORDER BY order_month;

-- ------------------------------------------------------------
-- B. Headline KPIs for the Executive page
-- ------------------------------------------------------------
SELECT
    COUNT(DISTINCT o.order_id)                        AS total_orders,
    COUNT(DISTINCT c.customer_unique_id)              AS unique_customers,
    ROUND(SUM(p.payment_value), 2)                    AS total_revenue,
    ROUND(SUM(p.payment_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    ROUND(AVG(order_level.order_value), 2)            AS avg_order_value_v2,
    MIN(DATE(o.order_purchase_timestamp))             AS first_order_date,
    MAX(DATE(o.order_purchase_timestamp))             AS last_order_date
FROM orders o
JOIN order_payments p ON p.order_id = o.order_id
JOIN customers c      ON c.customer_id = o.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS order_value
    FROM order_payments GROUP BY order_id
) order_level ON order_level.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');

-- ------------------------------------------------------------
-- C. Revenue by payment type (useful executive slice)
-- ------------------------------------------------------------
SELECT
    p.payment_type,
    COUNT(DISTINCT p.order_id)        AS orders_count,
    ROUND(SUM(p.payment_value), 2)    AS revenue,
    ROUND(AVG(p.payment_installments), 1) AS avg_installments
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY p.payment_type
ORDER BY revenue DESC;
