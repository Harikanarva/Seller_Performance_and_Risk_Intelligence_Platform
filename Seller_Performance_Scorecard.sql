DROP DATABASE IF EXISTS olist_seller_performance;
CREATE DATABASE olist_seller_performance;
USE olist_seller_performance;
create table stg_order_items (
order_id    varchar(50),
order_item_id    varchar(50),
product_id        varchar(50),
seller_id     varchar(50),
shipping_limit_date  varchar(50),
price      decimal(12,2),
freight_value     decimal(12,2));

create table stg_order_reviews (
    review_id                  varchar(50),
    order_id                    varchar(50),
    review_score                 int,
    review_comment_title          text,
    review_comment_message         text,
    review_creation_date            varchar(50),
    review_answer_timestamp          varchar(50)
);

create table stg_order (
order_id         varchar(50),
customer_id    varchar(50),
order_status       text,
order_purchase_timestamp   varchar(50),
order_approved_at   varchar(50),
order_delivered_carrier_date           varchar(50),
order_delivered_customer_date         varchar(50),
order_estimated_date             varchar(50));

create table stg_seller (
seller_id     varchar(50),
seller_zipcode   varchar(10),
seller_city   varchar(50),
seller_state   char(2));

create table stg_customer (
customer_id     varchar(50),
unique_customer_id   varchar(50),
customer_zipcode varchar(10),
city  varchar(50),
state char(2));

create table stg_product (
product_id     varchar(50),
product_category_name     varchar(50),
product_name_length     INT,
description_length     INT,
product_photos_qty      INT,
product_weight_g      INT,
product_length_cm      INT,
product_height_cm     INT,
product_width_cm       INT);

create table stg_product_category_name_translation (
product_category_name   varchar(50),
product_category_name_english         varchar(50) );

alter table stg_product
rename column description_length to product_decription_length;

alter table stg_product
rename column product_decription_length to product_description_length;

select count(*) from stg_order_reviews;
 alter table stg_customer
 rename column customer_zipcode to customer_zip_code_prefix,
 rename column city to customer_city,
 rename column state to customer_state;
 
alter table stg_customer
rename column unique_customer_id to customer_unique_id;
alter table stg_order
rename column order_estimated_date to order_estimated_delivery_date;


create database if not exists olist_seller_performance;
use olist_seller_performance;
alter table stg_order
rename column order_estimated_date to order_estimated_delivery_date;
alter table stg_seller
rename column seller_zipcode to seller_zip_code_prefix;

-- =========================================================
-- 0. Duplicates — check and remove across all raw tables first.
-- =========================================================

SELECT order_id, COUNT(*) 
FROM stg_order
GROUP BY order_id 
HAVING COUNT(*) > 1;

select customer_id, count(*)
from stg_customer
group by customer_id
having count(*) >1;

select product_id, count(*)
from stg_product
group by product_id
having count(*) > 1;

select seller_id, count(*)
from stg_seller
group by seller_id
having count(*) > 1;



CREATE TABLE raw_orders_dedup AS
SELECT DISTINCT * FROM raw_orders;


-- =========================================================
-- 1. raw_customers
-- =========================================================

-- Nulls in key columns
SELECT
    SUM(customer_id IS NULL)   AS null_customer_id,
    SUM(customer_city IS NULL) AS null_city,
    SUM(customer_state IS NULL) AS null_state
FROM raw_customers;

-- Standardize text fields — city names in Olist are inconsistently
-- cased/spaced ('sao paulo', 'Sao Paulo', ' sao paulo')
UPDATE raw_customers
SET customer_city = LOWER(TRIM(customer_city)),
    customer_state = UPPER(TRIM(customer_state));

-- State codes should be exactly 2 chars — flag anything that isn't
SELECT DISTINCT customer_state
FROM raw_customers
WHERE LENGTH(customer_state) != 2;


-- =========================================================
-- 2. raw_sellers
-- =========================================================

UPDATE raw_sellers
SET seller_city = LOWER(TRIM(seller_city)),
    seller_state = UPPER(TRIM(seller_state));

SELECT DISTINCT seller_state
FROM raw_sellers
WHERE LENGTH(seller_state) != 2;

-- Orphan check: sellers with zero order_items (not an error, but
-- worth knowing before build the scorecard — these sellers
-- will never appear in it)
SELECT s.seller_id
FROM raw_sellers s
LEFT JOIN raw_order_items oi ON s.seller_id = oi.seller_id
WHERE oi.seller_id IS NULL;


-- =========================================================
-- 3. raw_products
-- =========================================================

SELECT COUNT(*) AS null_category
FROM raw_products
WHERE product_category_name IS NULL;

UPDATE raw_products
SET product_category_name = 'uncategorized'
WHERE product_category_name IS NULL;

-- Olist ships category names in Portuguese with a separate
-- translation file (product_category_name_translation.csv).
-- Join it in now, not later in Power BI, so every downstream
-- table already has English category names.
ALTER TABLE raw_products ADD COLUMN product_category_name_en VARCHAR(100);

UPDATE raw_products p
JOIN product_category_translation t
    ON p.product_category_name = t.product_category_name
SET p.product_category_name_en = t.product_category_name_english;

-- Any category that didn't find a translation match
SELECT DISTINCT product_category_name
FROM raw_products
WHERE product_category_name_en IS NULL
  AND product_category_name != 'uncategorized';

-- Physical dimension outliers — a product with 0 or NULL weight
-- will break any freight-ratio calculation downstream
SELECT COUNT(*)
FROM raw_products
WHERE product_weight_g IS NULL OR product_weight_g = 0;


-- =========================================================
-- 4. raw_orders
-- =========================================================

-- Date logic sanity checks — these catch real data quality bugs,
-- not just missing values
SELECT COUNT(*) AS delivered_before_purchase
FROM raw_orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

SELECT COUNT(*) AS approved_before_purchase
FROM raw_orders
WHERE order_approved_at < order_purchase_timestamp;

-- Orders marked 'delivered' but missing a delivery date —
-- these will break the on_time_flag logic in the scorecard view,
-- so they need a decision now, not silently later
SELECT COUNT(*)
FROM raw_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- Decision: exclude these from fact_order_items rather than
-- guess a delivery date — flag them so you can state the
-- exclusion count explicitly in your data notes
DELETE FROM raw_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- order_status values — confirm no unexpected values slipped in
-- beyond what dim_order_status already covers
SELECT DISTINCT order_status
FROM raw_orders
WHERE order_status NOT IN (
    'delivered','shipped','invoiced','processing',
    'created','approved','canceled','unavailable'
);


-- =========================================================
-- 5. raw_order_items
-- =========================================================

-- Negative or zero price/freight — shouldn't exist, but check
SELECT COUNT(*)
FROM raw_order_items
WHERE price <= 0 OR freight_value < 0;

-- Orphan check: order_items referencing an order_id that doesn't
-- exist in raw_orders (can happen after the delivered-date DELETE
-- above — re-run this check after cleaning raw_orders)
SELECT oi.order_id
FROM raw_order_items oi
LEFT JOIN raw_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Orphan check: order_items referencing a product_id or seller_id
-- not present in the cleaned dimension source tables
SELECT oi.order_item_id
FROM raw_order_items oi
LEFT JOIN raw_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT oi.order_item_id
FROM raw_order_items oi
LEFT JOIN raw_sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


-- =========================================================
-- 6. raw_order_reviews
-- =========================================================

-- review_score should be strictly 1-5
SELECT DISTINCT review_score
FROM raw_order_reviews
WHERE review_score NOT BETWEEN 1 AND 5;

-- Multiple reviews per order_id happens in this dataset (rare but
-- real) — decide how to collapse before the LEFT JOIN in your
-- fact table load, or you'll silently duplicate order_items rows
SELECT order_id, COUNT(*) AS review_count
FROM raw_order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Keep the most recent review per order if duplicates exist
CREATE TABLE raw_order_reviews_dedup AS
SELECT r.*
FROM raw_order_reviews r
INNER JOIN (
    SELECT order_id, MAX(review_creation_date) AS max_date
    FROM raw_order_reviews
    GROUP BY order_id
) latest
    ON r.order_id = latest.order_id
   AND r.review_creation_date = latest.max_date;
   
-- stg_orders
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_id) AS unique_ids
FROM stg_order;

-- stg_order_items
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT CONCAT(order_id, order_item_id)) AS unique_ids
FROM stg_order_items;

-- stg_sellers
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT seller_id) AS unique_ids
FROM stg_seller;

-- stg_customers
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT customer_id) AS unique_ids
FROM stg_customer;

-- stg_products
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT product_id) AS unique_ids
FROM stg_product;

-- stg_order_reviews
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT review_id) AS unique_ids
FROM stg_order_reviews;

-- Diagnose
SELECT COUNT(*) AS total, COUNT(DISTINCT order_id) AS unique_ids FROM stg_order;
SELECT COUNT(*) FROM stg_order WHERE order_delivered_customer_date < order_purchase_timestamp;

-- Fix (build fact_orders clean)
CREATE TABLE fact_order AS
SELECT DISTINCT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM stg_order
WHERE order_id IS NOT NULL
  AND (order_delivered_customer_date IS NULL 
       OR order_delivered_customer_date >= order_purchase_timestamp);
       
describe stg_order;
describe stg_customer;
describe stg_order_items;
describe stg_order_reviews;
describe stg_product;
describe stg_product_category_name_translation;
describe stg_seller;
select order_id,order_purchase_timestamp,order_delivered_customer_date,order_estimated_delivery_date from stg_order limit 5;
CREATE TABLE fact_order AS
SELECT DISTINCT
    order_id,
    customer_id,
    order_status,
    STR_TO_DATE(order_purchase_timestamp, '%d-%m-%Y %H:%i') AS order_purchase_timestamp,
    STR_TO_DATE(order_delivered_customer_date, '%d-%m-%Y %H:%i') AS order_delivered_customer_date,
    STR_TO_DATE(order_estimated_delivery_date, '%d-%m-%Y %H:%i') AS order_estimated_delivery_date
FROM stg_order
WHERE order_id IS NOT NULL
  AND (order_delivered_customer_date IS NULL 
       OR STR_TO_DATE(order_delivered_customer_date, '%d-%m-%Y %H:%i') 
          >= STR_TO_DATE(order_purchase_timestamp, '%d-%m-%Y %H:%i'));
SELECT COUNT(*) 
FROM stg_order
WHERE STR_TO_DATE(order_delivered_customer_date, '%d-%m-%Y %H:%i') 
      < STR_TO_DATE(order_purchase_timestamp, '%d-%m-%Y %H:%i');         
CREATE TABLE fact_order_items AS
SELECT DISTINCT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    STR_TO_DATE(shipping_limit_date, '%d-%m-%Y %H:%i') AS shipping_limit_date,
    price,
    freight_value
FROM stg_order_items
WHERE order_id IS NOT NULL
  AND seller_id IS NOT NULL
  AND price > 0;
SELECT review_id, review_creation_date, review_answer_timestamp
FROM stg_order_reviews
LIMIT 5;

CREATE TABLE fact_reviews AS
SELECT r.review_id, 
       r.order_id, 
       r.review_score,
       STR_TO_DATE(r.review_creation_date, '%Y-%m-%d %H:%i:%s') AS review_creation_date,
       STR_TO_DATE(r.review_answer_timestamp, '%Y-%m-%d %H:%i:%s') AS review_answer_timestamp
FROM stg_order_reviews r
INNER JOIN (
    SELECT order_id, 
           MAX(STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s')) AS latest_date
    FROM stg_order_reviews
    GROUP BY order_id
) latest 
    ON r.order_id = latest.order_id 
    AND STR_TO_DATE(r.review_creation_date, '%Y-%m-%d %H:%i:%s') = latest.latest_date
WHERE r.review_score BETWEEN 1 AND 5;
select count(*) from fact_reviews; 
select count(*) from fact_order;
select count(*) from fact_order_items;
select order_id, shipping_limit_date from stg_order_items limit 5;          
	
SET SESSION cte_max_recursion_depth = 2000;

CREATE TABLE dim_date AS
WITH RECURSIVE date_range AS (
    SELECT DATE('2016-01-01') AS date_key
    UNION ALL
    SELECT DATE_ADD(date_key, INTERVAL 1 DAY)
    FROM date_range
    WHERE date_key < '2018-12-31'
)
SELECT
    date_key,
    YEAR(date_key) AS year,
    MONTH(date_key) AS month,
    QUARTER(date_key) AS quarter,
    DAYOFWEEK(date_key) - 1 AS day_of_week,
    CASE WHEN DAYOFWEEK(date_key) IN (1,7) THEN TRUE ELSE FALSE END AS is_weekend,
    DATE_FORMAT(date_key, '%M') AS month_name
FROM date_range;
          
select count(*) from dim_date;
CREATE TABLE dim_seller AS
SELECT DISTINCT seller_id, seller_zip_code_prefix, 
       COALESCE(seller_city, 'unknown') AS seller_city, 
       COALESCE(seller_state, 'unknown') AS seller_state
FROM stg_seller
WHERE seller_id IS NOT NULL;

CREATE TABLE dim_customer AS
SELECT DISTINCT customer_id, customer_unique_id, customer_zip_code_prefix,
       COALESCE(customer_city, 'unknown') AS customer_city,
       COALESCE(customer_state, 'unknown') AS customer_state
FROM stg_customer
WHERE customer_id IS NOT NULL;

CREATE TABLE dim_products AS
SELECT DISTINCT product_id,
       COALESCE(product_category_name, 'unknown') AS product_category_name,
       product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM stg_product
WHERE product_id IS NOT NULL;
select count(*) from dim_seller;
select count(*) from dim_customer;
select count(*) from dim_products;
          
          
          
          
          
          