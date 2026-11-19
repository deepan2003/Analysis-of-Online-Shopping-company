-- ============================================================
-- 00_create_database.sql
-- Project : E-Commerce Analytics (Olist Brazilian E-Commerce)
-- Engine  : MySQL 8.0+ / MariaDB 10.?+ (MySQL-compatible)
-- Purpose : Create the analytics database and the 9 raw tables.
-- Run with: mysql --local-infile=1 -u root < 00_create_database.sql
-- ============================================================

DROP DATABASE IF EXISTS ecommerce_analytics;
CREATE DATABASE ecommerce_analytics
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
USE ecommerce_analytics;

-- ------------------------------------------------------------
-- 1. customers : one row per order-customer link
--    customer_id        = surrogate key (unique per order)
--    customer_unique_id = the real person across orders
-- ------------------------------------------------------------
CREATE TABLE customers (
  customer_id              CHAR(32)    NOT NULL,
  customer_unique_id       CHAR(32)    NOT NULL,
  customer_zip_code_prefix VARCHAR(10) NULL,
  customer_city            VARCHAR(64) NULL,
  customer_state           CHAR(2)     NULL,
  PRIMARY KEY (customer_id),
  KEY idx_customers_unique (customer_unique_id),
  KEY idx_customers_state  (customer_state)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 2. orders : order header + full delivery timeline
-- ------------------------------------------------------------
CREATE TABLE orders (
  order_id                       CHAR(32) NOT NULL,
  customer_id                    CHAR(32) NULL,
  order_status                   VARCHAR(20) NULL,
  order_purchase_timestamp       DATETIME NULL,
  order_approved_at              DATETIME NULL,
  order_delivered_carrier_date   DATETIME NULL,
  order_delivered_customer_date  DATETIME NULL,
  order_estimated_delivery_date  DATETIME NULL,
  PRIMARY KEY (order_id),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_purchase (order_purchase_timestamp),
  KEY idx_orders_status   (order_status)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. order_items : one row per item inside an order
-- ------------------------------------------------------------
CREATE TABLE order_items (
  order_id            CHAR(32)       NOT NULL,
  order_item_id       INT            NOT NULL,
  product_id          CHAR(32)       NULL,
  seller_id           CHAR(32)       NULL,
  shipping_limit_date DATETIME       NULL,
  price               DECIMAL(10,2)  NULL,
  freight_value       DECIMAL(10,2)  NULL,
  PRIMARY KEY (order_id, order_item_id),
  KEY idx_items_product (product_id),
  KEY idx_items_seller  (seller_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 4. order_payments : 1..n payment rows per order
--    Revenue must always be SUM(payment_value), never a raw join
--    of orders x payments x items (that multiplies rows).
-- ------------------------------------------------------------
CREATE TABLE order_payments (
  order_id             CHAR(32)      NOT NULL,
  payment_sequential   INT           NOT NULL,
  payment_type         VARCHAR(30)   NULL,
  payment_installments INT           NULL,
  payment_value        DECIMAL(10,2) NULL,
  PRIMARY KEY (order_id, payment_sequential),
  KEY idx_pay_type (payment_type)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 5. order_reviews
-- ------------------------------------------------------------
CREATE TABLE order_reviews (
  review_id              CHAR(32)  NOT NULL,
  order_id               CHAR(32)  NOT NULL,
  review_score           TINYINT   NULL,
  review_comment_title   TEXT      NULL,
  review_comment_message TEXT      NULL,
  review_creation_date   DATETIME  NULL,
  review_answer_timestamp DATETIME NULL,
  PRIMARY KEY (review_id, order_id),
  KEY idx_reviews_order (order_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 6. products
-- ------------------------------------------------------------
CREATE TABLE products (
  product_id                 CHAR(32)    NOT NULL,
  product_category_name      VARCHAR(100) NULL,
  product_name_lenght        INT         NULL,
  product_description_lenght INT         NULL,
  product_photos_qty         INT         NULL,
  product_weight_g           INT         NULL,
  product_length_cm          INT         NULL,
  product_height_cm          INT         NULL,
  product_width_cm           INT         NULL,
  PRIMARY KEY (product_id),
  KEY idx_products_category (product_category_name)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 7. sellers
-- ------------------------------------------------------------
CREATE TABLE sellers (
  seller_id              CHAR(32)    NOT NULL,
  seller_zip_code_prefix VARCHAR(10) NULL,
  seller_city            VARCHAR(64) NULL,
  seller_state           CHAR(2)     NULL,
  PRIMARY KEY (seller_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 8. geolocation : zip prefix -> lat / lng (heavily duplicated)
-- ------------------------------------------------------------
CREATE TABLE geolocation (
  geolocation_zip_code_prefix VARCHAR(10)    NULL,
  geolocation_lat             DECIMAL(11,8) NULL,
  geolocation_lng             DECIMAL(11,8) NULL,
  geolocation_city            VARCHAR(64)    NULL,
  geolocation_state           CHAR(2)        NULL,
  KEY idx_geo_zip (geolocation_zip_code_prefix)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 9. product_category_name_translation
-- ------------------------------------------------------------
CREATE TABLE product_category_name_translation (
  product_category_name         VARCHAR(100) NOT NULL,
  product_category_name_english VARCHAR(100) NULL,
  PRIMARY KEY (product_category_name)
) ENGINE=InnoDB;
