-- ============================================================
-- Olist Brazilian E-Commerce Dataset — MySQL Schema
-- Create order matters due to foreign key dependencies:
-- lookup/dimension tables first, then orders, then child tables.
-- ============================================================

CREATE DATABASE IF NOT EXISTS olist_ecommerce
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 1. Dimension / lookup tables (no dependencies)
-- ------------------------------------------------------------

CREATE TABLE customers (
    customer_id              CHAR(32)     NOT NULL,
    customer_unique_id       CHAR(32)     NOT NULL,
    customer_zip_code_prefix CHAR(5)      NOT NULL,
    customer_city            VARCHAR(100) NOT NULL,
    customer_state           CHAR(2)      NOT NULL,
    PRIMARY KEY (customer_id),
    INDEX idx_customer_unique (customer_unique_id),
    INDEX idx_customer_state (customer_state)
) ENGINE=InnoDB;

CREATE TABLE sellers (
    seller_id              CHAR(32)     NOT NULL,
    seller_zip_code_prefix CHAR(5)      NOT NULL,
    seller_city            VARCHAR(100) NOT NULL,
    seller_state           CHAR(2)      NOT NULL,
    PRIMARY KEY (seller_id),
    INDEX idx_seller_state (seller_state)
) ENGINE=InnoDB;

CREATE TABLE product_category_name_translation (
    product_category_name          VARCHAR(100) NOT NULL,
    product_category_name_english  VARCHAR(100) NOT NULL,
    PRIMARY KEY (product_category_name)
) ENGINE=InnoDB;

CREATE TABLE products (
    product_id                  CHAR(32)     NOT NULL,
    product_category_name       VARCHAR(100)     NULL,  -- some products have no category
    product_name_lenght         SMALLINT         NULL,
    product_description_lenght  SMALLINT         NULL,
    product_photos_qty          SMALLINT         NULL,
    product_weight_g            INT              NULL,
    product_length_cm           SMALLINT         NULL,
    product_height_cm           SMALLINT         NULL,
    product_width_cm            SMALLINT         NULL,
    PRIMARY KEY (product_id),
    INDEX idx_product_category (product_category_name),
    CONSTRAINT fk_products_category
        FOREIGN KEY (product_category_name)
        REFERENCES product_category_name_translation (product_category_name)
        ON DELETE SET NULL
) ENGINE=InnoDB;

-- Geolocation has many duplicate/near-duplicate rows per zip prefix
-- (no natural single-column primary key) — load as-is, dedupe in SQL later.
CREATE TABLE geolocation (
    geolocation_zip_code_prefix CHAR(5)         NOT NULL,
    geolocation_lat              DECIMAL(10,7)  NOT NULL,
    geolocation_lng              DECIMAL(10,7)  NOT NULL,
    geolocation_city             VARCHAR(100)   NOT NULL,
    geolocation_state            CHAR(2)        NOT NULL,
    INDEX idx_geo_zip (geolocation_zip_code_prefix)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 2. Orders (depends on customers)
-- ------------------------------------------------------------

CREATE TABLE orders (
    order_id                       CHAR(32)    NOT NULL,
    customer_id                    CHAR(32)    NOT NULL,
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp       DATETIME    NOT NULL,
    order_approved_at              DATETIME        NULL,
    order_delivered_carrier_date   DATETIME        NULL,
    order_delivered_customer_date  DATETIME        NULL,
    order_estimated_delivery_date  DATETIME    NOT NULL,
    PRIMARY KEY (order_id),
    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_purchase_ts (order_purchase_timestamp),
    INDEX idx_orders_status (order_status),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. Child tables (depend on orders, products, sellers)
-- ------------------------------------------------------------

CREATE TABLE order_items (
    order_id            CHAR(32)      NOT NULL,
    order_item_id       SMALLINT      NOT NULL,
    product_id          CHAR(32)      NOT NULL,
    seller_id           CHAR(32)      NOT NULL,
    shipping_limit_date DATETIME      NOT NULL,
    price               DECIMAL(10,2) NOT NULL,
    freight_value       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id),
    INDEX idx_items_product (product_id),
    INDEX idx_items_seller (seller_id),
    CONSTRAINT fk_items_order
        FOREIGN KEY (order_id)
        REFERENCES orders (order_id),
    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id)
        REFERENCES products (product_id),
    CONSTRAINT fk_items_seller
        FOREIGN KEY (seller_id)
        REFERENCES sellers (seller_id)
) ENGINE=InnoDB;

CREATE TABLE order_payments (
    order_id             CHAR(32)      NOT NULL,
    payment_sequential   SMALLINT      NOT NULL,
    payment_type         VARCHAR(20)   NOT NULL,
    payment_installments SMALLINT      NOT NULL,
    payment_value        DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id)
        REFERENCES orders (order_id)
) ENGINE=InnoDB;

CREATE TABLE order_reviews (
    review_id               CHAR(32)  NOT NULL,
    order_id                CHAR(32)  NOT NULL,
    review_score            TINYINT   NOT NULL,
    review_comment_title    VARCHAR(255)  NULL,
    review_comment_message  TEXT          NULL,
    review_creation_date    DATETIME  NOT NULL,
    review_answer_timestamp DATETIME  NOT NULL,
    PRIMARY KEY (review_id, order_id),
    INDEX idx_reviews_order (order_id),
    CONSTRAINT fk_reviews_order
        FOREIGN KEY (order_id)
        REFERENCES orders (order_id)
) ENGINE=InnoDB;

-- ============================================================
-- Loading data (run after creating tables)
-- Adjust paths; requires local_infile enabled on the server/client:
--   SET GLOBAL local_infile = 1;
-- ============================================================

-- Example for one table — repeat pattern for the rest, loading in this order:
-- customers, sellers, product_category_name_translation, products,
-- orders, order_items, order_payments, order_reviews, geolocation

-- LOAD DATA LOCAL INFILE '/path/to/olist_customers_dataset.csv'
-- INTO TABLE customers
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS
-- (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state);
-- ============================================================
-- Olist Dataset — Load all CSVs into MySQL
-- Run AFTER olist_schema_mysql.sql has created the tables.
-- Load order matters (respects foreign key dependencies).
--
-- Before running, enable local_infile on both server and client:
--   SET GLOBAL local_infile = 1;
-- and connect with: mysql --local-infile=1 -u <user> -p
--
-- Adjust the file paths below to wherever your CSVs live.
-- ============================================================
-- ============================================================
-- Olist Dataset — Load all CSVs into MySQL
-- Run AFTER olist_schema_mysql.sql has created the tables.
-- Load order matters (respects foreign key dependencies).
--
-- FIX FOR ERROR 3948: switched from LOAD DATA LOCAL INFILE to
-- LOAD DATA INFILE (no LOCAL). This reads the file server-side
-- instead of client-side, which avoids the local_infile
-- client/server permission issue entirely — as long as your CSVs
-- sit inside MySQL's secure_file_priv directory, which yours do
-- (C:\ProgramData\MySQL\MySQL Server 8.0\Uploads\), this just works.
-- ============================================================

SHOW VARIABLES LIKE 'secure_file_priv';

USE olist_ecommerce;

SET FOREIGN_KEY_CHECKS = 0;  -- avoid load-order issues; re-enabled at the end

-- ------------------------------------------------------------
-- 1. customers
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state);

-- ------------------------------------------------------------
-- 2. sellers
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- ------------------------------------------------------------
-- 3. product_category_name_translation
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_category_name, product_category_name_english);

-- ------------------------------------------------------------
-- 4. products
-- Note: numeric columns can be blank in the source file, so we
-- load into user variables and convert '' to NULL.
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, @category, @name_len, @desc_len, @photos_qty,
 @weight_g, @length_cm, @height_cm, @width_cm)
SET
    product_category_name      = NULLIF(@category, ''),
    product_name_lenght        = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@desc_len, ''),
    product_photos_qty         = NULLIF(@photos_qty, ''),
    product_weight_g           = NULLIF(@weight_g, ''),
    product_length_cm          = NULLIF(@length_cm, ''),
    product_height_cm          = NULLIF(@height_cm, ''),
    product_width_cm           = NULLIF(@width_cm, '');

-- ------------------------------------------------------------
-- 5. orders
-- Several date columns can be blank (e.g. undelivered orders).
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_status, order_purchase_timestamp,
 @approved_at, @delivered_carrier, @delivered_customer, order_estimated_delivery_date)
SET
    order_approved_at             = NULLIF(@approved_at, ''),
    order_delivered_carrier_date  = NULLIF(@delivered_carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered_customer, '');

-- ------------------------------------------------------------
-- 6. order_items
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value);

-- ------------------------------------------------------------
-- 7. order_payments
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, payment_sequential, payment_type, payment_installments, payment_value);

-- ------------------------------------------------------------
-- 8. order_reviews
-- Title/message can be blank; review_id repeats in rare cases so
-- we load with a duplicate-key-safe REPLACE.
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_order_reviews_dataset_clean.csv'
REPLACE
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(review_id, order_id, review_score, @title, @message,
 review_creation_date, review_answer_timestamp)
SET
    review_comment_title   = NULLIF(@title, ''),
    review_comment_message = NULLIF(@message, '');

-- ------------------------------------------------------------
-- 9. geolocation (large file, ~1M rows — may take a minute)
-- ------------------------------------------------------------
LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
 geolocation_city, geolocation_state);

SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------
-- Quick sanity check — row counts should roughly match the CSVs
-- ------------------------------------------------------------
-- Row-count sanity check (fixed: "rows" is a reserved word in MySQL 8.0,
-- renamed the alias to row_count)
SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation;
-- ============================================================
-- Olist E-Commerce — Core Analysis Queries
-- Run after schema + data load are complete.
-- Only counts delivered/valid orders as "revenue" (excludes
-- canceled/unavailable orders) throughout, unless noted.
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 0. BASE VIEW — the single joined table almost everything
--    below builds on. One row per order item.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_order_items_full AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_state,
    c.customer_city,
    o.order_status,
    o.order_purchase_timestamp,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_year_month,
    oi.order_item_id,
    oi.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_english,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS item_total
FROM orders o
JOIN order_items oi          ON oi.order_id = o.order_id
JOIN customers c              ON c.customer_id = o.customer_id
LEFT JOIN products p          ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = p.product_category_name
WHERE o.order_status NOT IN ('canceled', 'unavailable');


-- ------------------------------------------------------------
-- 1. REVENUE BY CATEGORY — which categories drive revenue
-- ------------------------------------------------------------
SELECT
    category_english,
    COUNT(DISTINCT order_id)              AS order_count,
    SUM(price)                            AS total_revenue,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(100 * SUM(price) / SUM(SUM(price)) OVER (), 2) AS pct_of_total_revenue
FROM vw_order_items_full
GROUP BY category_english
ORDER BY total_revenue DESC
LIMIT 20;


-- ------------------------------------------------------------
-- 2. REVENUE BY REGION (state) — geographic performance
-- ------------------------------------------------------------
SELECT
    customer_state,
    COUNT(DISTINCT order_id)              AS order_count,
    SUM(price)                            AS total_revenue,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(AVG(freight_value), 2)          AS avg_freight_value
FROM vw_order_items_full
GROUP BY customer_state
ORDER BY total_revenue DESC;


-- ------------------------------------------------------------
-- 3. CATEGORY x REGION MATRIX — top category per state
-- ------------------------------------------------------------
WITH cat_region AS (
    SELECT
        customer_state,
        category_english,
        SUM(price) AS revenue,
        RANK() OVER (PARTITION BY customer_state ORDER BY SUM(price) DESC) AS rnk
    FROM vw_order_items_full
    GROUP BY customer_state, category_english
)
SELECT customer_state, category_english AS top_category, revenue
FROM cat_region
WHERE rnk = 1
ORDER BY revenue DESC;


-- ------------------------------------------------------------
-- 4. MONTHLY REVENUE TREND + MONTH-OVER-MONTH GROWTH
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT
        order_year_month,
        SUM(price) AS revenue
    FROM vw_order_items_full
    GROUP BY order_year_month
)
SELECT
    order_year_month,
    revenue,
    LAG(revenue) OVER (ORDER BY order_year_month) AS prev_month_revenue,
    ROUND(
        100 * (revenue - LAG(revenue) OVER (ORDER BY order_year_month))
        / LAG(revenue) OVER (ORDER BY order_year_month), 2
    ) AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (
        ORDER BY order_year_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3mo_avg_revenue
FROM monthly
ORDER BY order_year_month;


-- ------------------------------------------------------------
-- 5. SEASONALITY — revenue by calendar month, all years combined
--    (useful if you want a season-over-season view instead of
--    a strict monthly timeline)
-- ------------------------------------------------------------
SELECT
    MONTH(order_purchase_timestamp)   AS calendar_month,
    MONTHNAME(order_purchase_timestamp) AS month_name,
    SUM(price)                        AS total_revenue,
    COUNT(DISTINCT order_id)          AS order_count
FROM vw_order_items_full
GROUP BY calendar_month, month_name
ORDER BY calendar_month;


-- ------------------------------------------------------------
-- 6. AVERAGE ORDER VALUE — overall, and trended monthly
-- ------------------------------------------------------------
-- Overall AOV
SELECT ROUND(SUM(item_total) / COUNT(DISTINCT order_id), 2) AS overall_aov
FROM vw_order_items_full;

-- AOV trended by month
SELECT
    order_year_month,
    ROUND(SUM(item_total) / COUNT(DISTINCT order_id), 2) AS aov
FROM vw_order_items_full
GROUP BY order_year_month
ORDER BY order_year_month;


-- ------------------------------------------------------------
-- 7. FREIGHT COST AS % OF ORDER VALUE, BY REGION
--    (diagnostic: is shipping eating margin in some states?)
-- ------------------------------------------------------------
SELECT
    customer_state,
    ROUND(SUM(freight_value), 2)                         AS total_freight,
    ROUND(SUM(price), 2)                                 AS total_price,
    ROUND(100 * SUM(freight_value) / SUM(price), 2)       AS freight_pct_of_price
FROM vw_order_items_full
GROUP BY customer_state
ORDER BY freight_pct_of_price DESC;


-- ------------------------------------------------------------
-- 8. HIGH REVENUE BUT POOR REVIEWS — quality-risk categories
--    (diagnostic: where is revenue exposed to reputation risk?)
-- ------------------------------------------------------------
SELECT
    v.category_english,
    SUM(v.price)                       AS total_revenue,
    ROUND(AVG(r.review_score), 2)      AS avg_review_score,
    COUNT(DISTINCT r.review_id)        AS review_count
FROM vw_order_items_full v
JOIN order_reviews r ON r.order_id = v.order_id
GROUP BY v.category_english
HAVING review_count >= 30              -- ignore tiny/noisy categories
ORDER BY total_revenue DESC, avg_review_score ASC
LIMIT 20;


-- ------------------------------------------------------------
-- 9. DELIVERY PERFORMANCE BY REGION
--    (diagnostic: slow delivery states, vs. estimated date)
-- ------------------------------------------------------------
SELECT
    c.customer_state,
    COUNT(*)                                                    AS delivered_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1)
                                                                 AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)), 1)
                                                                 AS avg_days_vs_estimate
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;


-- ------------------------------------------------------------
-- 10. RFM SEGMENTATION — Recency, Frequency, Monetary per customer
--     (uses customer_unique_id since one person can have multiple
--      customer_id values across orders)
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        v.item_total
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    JOIN vw_order_items_full v ON v.order_id = o.order_id
),
rfm_base AS (
    SELECT
        customer_unique_id,
        DATEDIFF(
            (SELECT MAX(order_purchase_timestamp) FROM orders),
            MAX(order_purchase_timestamp)
        ) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(item_total)          AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,  -- 4 = most recent
        NTILE(4) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm_base
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champion'
        WHEN r_score >= 3 AND f_score <= 2                  THEN 'Recent, low frequency'
        WHEN r_score <= 2 AND f_score >= 3                  THEN 'At-risk (was frequent)'
        WHEN r_score <= 2 AND m_score <= 2                  THEN 'Lost / low value'
        ELSE 'Other'
    END AS segment
FROM rfm_scored
ORDER BY rfm_total DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 11. PAYMENT TYPE BREAKDOWN — how people pay, by installments
-- ------------------------------------------------------------
SELECT
    payment_type,
    COUNT(*)                          AS payment_count,
    ROUND(AVG(payment_installments),1) AS avg_installments,
    ROUND(SUM(payment_value), 2)      AS total_payment_value
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;
