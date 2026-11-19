-- ============================================================
-- 30_cohort_retention.sql
-- Business question: How many first-time buyers actually come back?
--
-- A cohort is the calendar month of a customer's FIRST valid order.
-- Month index 0 = acquisition month, 1 = the month after, and so on.
-- Retention % = customers from the cohort who ordered in month N
--               divided by the cohort size.
-- ============================================================

USE ecommerce_analytics;

-- ------------------------------------------------------------
-- A. Build the reusable cohort base table
--    (materialised so Power BI can query it directly)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS customer_cohort_base;
CREATE TABLE customer_cohort_base AS
WITH first_order AS (
    SELECT
        c.customer_unique_id,
        MIN(DATE(o.order_purchase_timestamp)) AS first_order_date
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
),
activity AS (
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS activity_month,
        STR_TO_DATE(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01'), '%Y-%m-%d') AS activity_month_date
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id,
             DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
             STR_TO_DATE(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01'), '%Y-%m-%d')
)
SELECT
    f.customer_unique_id,
    DATE_FORMAT(f.first_order_date, '%Y-%m')              AS cohort_month,
    STR_TO_DATE(DATE_FORMAT(f.first_order_date, '%Y-%m-01'), '%Y-%m-%d') AS cohort_month_date,
    a.activity_month,
    a.activity_month_date,
    TIMESTAMPDIFF(
        MONTH,
        STR_TO_DATE(DATE_FORMAT(f.first_order_date, '%Y-%m-01'), '%Y-%m-%d'),
        a.activity_month_date
    )                                                     AS month_index
FROM first_order f
JOIN activity a ON a.customer_unique_id = f.customer_unique_id;

ALTER TABLE customer_cohort_base
  ADD PRIMARY KEY (customer_unique_id, activity_month),
  ADD KEY idx_cohort (cohort_month),
  ADD KEY idx_month_index (month_index);

-- ------------------------------------------------------------
-- B. Cohort retention matrix (long format, months 0..6)
--    Month 0 is always 100% of the cohort.
-- ------------------------------------------------------------
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM customer_cohort_base
    GROUP BY cohort_month
),
matrix AS (
    SELECT
        b.cohort_month,
        b.month_index,
        COUNT(DISTINCT b.customer_unique_id) AS active_customers,
        s.cohort_customers
    FROM customer_cohort_base b
    JOIN cohort_size s ON s.cohort_month = b.cohort_month
    WHERE b.month_index BETWEEN 0 AND 6
    GROUP BY b.cohort_month, b.month_index, s.cohort_customers
)
SELECT
    cohort_month,
    cohort_customers,
    month_index,
    active_customers,
    ROUND(active_customers / cohort_customers * 100, 2) AS retention_pct,
    ROUND(100 - active_customers / cohort_customers * 100, 2) AS churn_pct,
    LAG(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_index) AS prev_month_active,
    ROUND(
        active_customers / NULLIF(LAG(active_customers) OVER
            (PARTITION BY cohort_month ORDER BY month_index), 0) * 100
    , 2) AS change_vs_prev_month_pct
FROM matrix
WHERE cohort_customers >= 50              -- ignore micro-cohorts with unstable percentages
ORDER BY cohort_month, month_index;

-- ------------------------------------------------------------
-- C. Average retention curve by month index (dashboard KPI)
-- ------------------------------------------------------------
WITH cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM customer_cohort_base
    GROUP BY cohort_month
),
per_cohort AS (
    SELECT
        b.cohort_month,
        b.month_index,
        COUNT(DISTINCT b.customer_unique_id) AS active_customers,
        s.cohort_customers,
        COUNT(DISTINCT b.customer_unique_id) / s.cohort_customers * 100 AS retention_pct
    FROM customer_cohort_base b
    JOIN cohort_size s ON s.cohort_month = b.cohort_month
    WHERE b.month_index BETWEEN 0 AND 6
      AND s.cohort_customers >= 50      -- ignore micro-cohorts
    GROUP BY b.cohort_month, b.month_index, s.cohort_customers
)
SELECT
    month_index,
    SUM(active_customers)          AS active_customers,
    ROUND(AVG(retention_pct), 2)   AS avg_retention_pct,
    ROUND(SUM(active_customers) / SUM(cohort_customers) * 100, 2) AS weighted_retention_pct,
    ROUND(MIN(retention_pct), 2)   AS min_retention_pct,
    ROUND(MAX(retention_pct), 2)   AS max_retention_pct,
    COUNT(*)                       AS cohorts_included
FROM per_cohort
GROUP BY month_index
ORDER BY month_index;

-- ------------------------------------------------------------
-- D. Did a buyer ever place a SECOND order? (LEAD window function)
--    Also reports the share that returned the very next month.
-- ------------------------------------------------------------
WITH order_seq AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        LEAD(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS next_order_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS order_number
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
),
first_purchase AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp AS first_order_at,
        order_month              AS cohort_month,
        next_order_timestamp,
        TIMESTAMPDIFF(
            MONTH,
            STR_TO_DATE(DATE_FORMAT(order_purchase_timestamp, '%Y-%m-01'), '%Y-%m-%d'),
            STR_TO_DATE(DATE_FORMAT(next_order_timestamp, '%Y-%m-01'), '%Y-%m-%d')
        ) AS months_to_second_order
    FROM order_seq
    WHERE order_number = 1
)
SELECT
    cohort_month,
    COUNT(*)                                                          AS new_customers,
    SUM(next_order_timestamp IS NOT NULL)                             AS returned_customers,
    ROUND(SUM(next_order_timestamp IS NOT NULL) / COUNT(*) * 100, 2)   AS repeat_rate_pct,
    ROUND(SUM(months_to_second_order = 1) / COUNT(*) * 100, 2)         AS returned_in_month_1_pct,
    ROUND(AVG(months_to_second_order), 2)                              AS avg_months_to_return
FROM first_purchase
GROUP BY cohort_month
ORDER BY cohort_month;

-- ------------------------------------------------------------
-- E. Overall repeat-purchase KPI
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                   AS total_customers,
    SUM(order_count > 1)                                       AS repeat_customers,
    ROUND(SUM(order_count > 1) / COUNT(*) * 100, 2)            AS repeat_rate_pct,
    ROUND(AVG(order_count), 3)                                 AS avg_orders_per_customer
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
) t;
