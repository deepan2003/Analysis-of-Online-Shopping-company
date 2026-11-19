-- ============================================================
-- 01_load_data.sql
-- Loads the 9 raw Olist CSV files into ecommerce_analytics.
-- Prerequisite: 00_create_database.sql has been run.
--
-- Run from a Windows shell (local_infile must be on for the client):
--   mysql --local-infile=1 -u root -p ecommerce_analytics < 01_load_data.sql
--
-- If your dataset lives elsewhere, edit the INFILE paths below.
-- Use forward slashes on Windows and keep the single quotes.
--
-- Reviews note: olist_order_reviews_dataset.csv contains embedded
-- newlines and backslashes inside free-text comments, which makes
-- LOAD DATA merge/skip rows. Section 5 therefore loads a cleaned
-- copy produced by sql/prep_reviews.py (exports/olist_order_reviews_clean.csv,
-- 99,224 rows, UTF-8, LF line endings).
-- ============================================================

USE ecommerce_analytics;


-- Safety: empty the tables so the script is re-runnable.
TRUNCATE TABLE product_category_name_translation;
TRUNCATE TABLE geolocation;
TRUNCATE TABLE sellers;
TRUNCATE TABLE products;
TRUNCATE TABLE order_reviews;
TRUNCATE TABLE order_payments;
TRUNCATE TABLE order_items;
TRUNCATE TABLE orders;
TRUNCATE TABLE customers;

-- ------------------------------------------------------------
-- 1. customers (99,441 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state);

-- ------------------------------------------------------------
-- 2. orders (99,441 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
 order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date)
SET
  order_purchase_timestamp      = NULLIF(order_purchase_timestamp, ''),
  order_approved_at             = NULLIF(order_approved_at, ''),
  order_delivered_carrier_date  = NULLIF(order_delivered_carrier_date, ''),
  order_delivered_customer_date = NULLIF(order_delivered_customer_date, ''),
  order_estimated_delivery_date = NULLIF(order_estimated_delivery_date, '');

-- ------------------------------------------------------------
-- 3. order_items (112,650 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value);

-- ------------------------------------------------------------
-- 4. order_payments (103,886 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, payment_value);

-- ------------------------------------------------------------
-- 5. order_reviews (99,224 rows) - cleaned copy, see header note
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/exports/olist_order_reviews_clean.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(review_id, order_id, review_score, review_comment_title, review_comment_message,
 review_creation_date, review_answer_timestamp);

-- ------------------------------------------------------------
-- 6. products (32,951 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, product_category_name, product_name_lenght, product_description_lenght,
 product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm);

-- ------------------------------------------------------------
-- 7. sellers (3,095 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- ------------------------------------------------------------
-- 8. geolocation (1,000,163 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
 geolocation_city, geolocation_state);

-- ------------------------------------------------------------
-- 9. product_category_name_translation (71 rows)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'D:/Analyst project 1/Dataset/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name, product_category_name_english);

-- ------------------------------------------------------------
-- Row-count audit (expected values in comments)
-- ------------------------------------------------------------
SELECT 'customers'   AS table_name, COUNT(*) AS rows_loaded FROM customers     -- 99,441
UNION ALL SELECT 'orders',    COUNT(*) FROM orders                             -- 99,441
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items                      -- 112,650
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments                -- 103,886
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews                  -- 99,224
UNION ALL SELECT 'products',  COUNT(*) FROM products                           -- 32,951
UNION ALL SELECT 'sellers',   COUNT(*) FROM sellers                            -- 3,095
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation                      -- 1,000,163
UNION ALL SELECT 'category_translation', COUNT(*) FROM product_category_name_translation; -- 71
