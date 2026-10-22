# E-Commerce Sales Intelligence Dashboard

**End-to-end analytics project on the Olist Brazilian e-commerce marketplace (~100K orders): raw CSVs → MySQL → SQL analysis → Power BI dashboard.**

<img width="3001" height="1688" alt="dashboard" src="https://github.com/user-attachments/assets/6bc5bdbc-0025-46fb-b1df-072959eacccf" />


| Revenue | Orders | Avg. order value | Period |
|:---:|:---:|:---:|:---:|
| **13.49M** | **98K** | **160.24** | Jan 2017 – Aug 2018 |

> Revenue = item price. Average order value includes freight (price + freight per order).


---


## Business problem

An online marketplace wants to understand where its revenue comes from and where it is exposed.

1. **Which product categories drive revenue?**
2. **How do sales move over time and across regions?** (month-over-month growth, seasonality, state-level split)
3. **Where are the risks?** Product quality (reviews), logistics (freight cost, delivery time) and payments.

The analysis is framed as **what is happening → why → what to do**: descriptive KPIs and trends first, then diagnostics (reviews, freight, delivery), then recommendations.

## Dataset

[Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle): 9 relational CSV files covering real orders placed on the Olist marketplace.

| Table | Rows | Role |
|---|---:|---|
| `orders` | 99,441 | Order header: status, purchase / delivery / estimated dates |
| `order_items` | 112,650 | Revenue grain: price and freight per item |
| `customers` | 99,441 | Customer state and city (region dimension) |
| `products` | 32,951 | Product attributes and category (Portuguese) |
| `product_category_name_translation` | 71 | Portuguese → English category names |
| `order_payments` | 103,886 | Payment type, installments, value |
| `order_reviews` | 99,224 (99,214 loaded) | Review score and comments |
| `sellers` | 3,095 | Seller location |
| `geolocation` | ~1,000,000 | Zip-prefix coordinates (loaded, not used in the dashboard) |


## Workflow

```
Kaggle CSVs (9 files)
        ↓
clean_reviews.py  (flatten line breaks in review comments)
        ↓
MySQL: schema → LOAD DATA → row-count check
        ↓
vw_order_items_full  (base SQL view)
        ↓
11 analysis queries  (window functions, CTEs, RFM)
        ↓
Power BI: Power Query → data model → DAX measures → dashboard
        ↓
Insights and suggested actions
```

---

## MySQL work

### Schema design 

Nine InnoDB tables with enforced keys, created in dependency order:

- **Primary keys:** single-column on `orders`, `customers`, `products`, `sellers`; **composite** on `order_items (order_id, order_item_id)`, `order_payments (order_id, payment_sequential)` and `order_reviews (review_id, order_id)`, because a single order can have several items and payments, and some `review_id` values repeat.
- **Foreign keys:** `orders → customers`; `order_items → orders / products / sellers`; `order_payments → orders`; `order_reviews → orders`; `products → product_category_name_translation` (nullable, `ON DELETE SET NULL`, since some products have no category).
- **Indexes** on the columns the analysis filters and joins on: `customer_state`, `seller_state`, `order_purchase_timestamp`, `order_status`, `product_category_name`.
- **Types:** `CHAR(32)` for hash IDs, `DECIMAL(10,2)` for money, `DATETIME` for timestamps.
- `geolocation` has no natural key (many rows per zip prefix), so it is loaded as a plain indexed table.

### Loading

- Server-side `LOAD DATA INFILE` from the `secure_file_priv` folder, with `FOREIGN_KEY_CHECKS` switched off during the load.
- Blank numeric and date fields converted to real `NULL`s with `NULLIF(@var, '')` (otherwise MySQL inserts `0` or `0000-00-00`).
- `order_reviews` loaded with `REPLACE` so repeated `(review_id, order_id)` pairs do not abort the load.
- A row-count check at the end of the script confirms every table loaded (`sql/olist_sanity_check.sql`).


### Analytical base view

`vw_order_items_full` is the single joined table the analysis and the dashboard are built on: one row per order item, joining `orders → order_items → customers → products → category translation`, excluding canceled and unavailable orders, with an English category name and `item_total = price + freight_value`.

```sql
CREATE OR REPLACE VIEW vw_order_items_full AS
SELECT o.order_id, o.customer_id, c.customer_state, c.customer_city, o.order_status,
       o.order_purchase_timestamp,
       DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_year_month,
       oi.order_item_id, oi.product_id,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_english,
       oi.seller_id, oi.price, oi.freight_value,
       (oi.price + oi.freight_value) AS item_total
FROM orders o
JOIN order_items oi  ON oi.order_id = o.order_id
JOIN customers c     ON c.customer_id = o.customer_id
LEFT JOIN products p ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation t ON t.product_category_name = p.product_category_name
WHERE o.order_status NOT IN ('canceled', 'unavailable');
```

### Analysis queries

| # | Question | SQL techniques |
|---|---|---|
| 1 | Revenue by category and share of total | `SUM() OVER ()` |
| 2 | Revenue, orders, AOV and freight by state | Aggregation |
| 3 | Top category in each state | CTE, `RANK() OVER (PARTITION BY …)` |
| 4 | Monthly revenue, MoM growth, rolling 3-month average | `LAG()`, window frame `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` |
| 5 | Seasonality by calendar month | `MONTH()`, `MONTHNAME()` |
| 6 | Average order value, overall and by month | Aggregation |
| 7 | Freight as % of price by state | Ratio of aggregates |
| 8 | Categories with high revenue but weak reviews | Join to reviews, `HAVING` (≥ 30 reviews) |
| 9 | Delivery time vs. estimate by state | `DATEDIFF`, null-safe filtering |
| 10 | Customer RFM segmentation | Chained CTEs, `NTILE(4)` |
| 11 | Payment-type mix and installments | Aggregation |

Example: monthly revenue with month-over-month growth and a rolling average.

```sql
WITH monthly AS (
    SELECT order_year_month, SUM(price) AS revenue
    FROM vw_order_items_full
    GROUP BY order_year_month
)
SELECT
    order_year_month,
    revenue,
    LAG(revenue) OVER (ORDER BY order_year_month) AS prev_month_revenue,
    ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY order_year_month))
              / LAG(revenue) OVER (ORDER BY order_year_month), 2) AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (ORDER BY order_year_month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3mo_avg_revenue
FROM monthly
ORDER BY order_year_month;
```

Selected SQL results (all non-canceled orders):

| Finding | Result |
|---|---|
| Revenue by state | SP 5.16M · RJ 1.81M · MG 1.57M · RS 0.74M · PR 0.68M |
| Highest freight share of price | RR 28.6% · MA 26.3% · RO 24.8% · AM 24.5% · PI 24.4% |
| Slowest average delivery | RR 29.3 days · AP 27.2 · AM 26.4 |
| Delivery vs. estimated date (those states) | 17–20 days **earlier** than estimated |
| Payment mix | Credit card 76.8K payments, 3.5 installments on average · boleto 19.8K, single payment |

---

## Power BI work

### Data model

- Tables loaded: `vw_order_items_full` (fact), `order_reviews`, `order_payments`, and a `DateTable`.
- `DateTable` built with `CALENDAR()`, with `Year`, `MonthNumber`, `MonthName` and `YearMonth` columns, **marked as a date table**; related one-to-many to a date-only `OrderDate` column derived from the purchase timestamp.
- `vw_order_items_full ↔ order_reviews` and `↔ order_payments` on `order_id` as **many-to-many with bidirectional filtering**, because `order_id` repeats on both sides (several items per order). Without these relationships the review score was identical (4.0864) for every category, because category filters never reached the reviews table. Adding them gave each category its own score.

### Power Query

- `order_purchase_timestamp` filtered to **2017-01-01 ≤ date < 2018-09-01** (full months only).
- `order_payments` **inner-merged** with the filtered items query on `order_id` (merge column then removed), so the payment donut covers exactly the same orders as the revenue figures. Result: payments **15.74M = item price 13.49M + freight 2.25M**, which matches `SUM(item_total)` exactly.

### DAX measures

```dax
Total Revenue       = SUM(vw_order_items_full[price])
Order Count         = DISTINCTCOUNT(vw_order_items_full[order_id])
Total Freight       = SUM(vw_order_items_full[freight_value])
AOV                 = DIVIDE([Total Revenue] + [Total Freight], [Order Count])
Freight Pct of Price = DIVIDE([Total Freight], [Total Revenue])

Revenue Prev Month  = CALCULATE([Total Revenue], DATEADD(DateTable[Date], -1, MONTH))
MoM Growth %        = DIVIDE([Total Revenue] - [Revenue Prev Month], [Revenue Prev Month])
Rolling 3mo Avg Revenue =
    CALCULATE(
        AVERAGEX(VALUES(DateTable[YearMonth]), [Total Revenue]),
        DATESINPERIOD(DateTable[Date], MAX(DateTable[Date]), -3, MONTH)
    )

Avg Review Score    = AVERAGE(order_reviews[review_score])
```

### Dashboard

Single 16:9 page with a custom dark theme (`dashboard/theme/olist_dark_theme.json`) and gradient background.

| Visual | Purpose |
|---|---|
| KPI cards: Total Revenue, Order Count, AOV | Headline numbers |
| Revenue by month (line) | Growth trajectory and the Black Friday spike |
| Month-over-month growth (line, %) | Whether growth is accelerating or slowing |
| Top 10 categories by revenue (bar) | What drives revenue |
| Top 10 states by revenue (treemap) | Geographic concentration |
| Review score of the top-10 revenue categories (bar, zoomed axis) | Quality risk where the money is |
| Freight cost as % of price by state (bar) | Logistics burden by region |
| Payment value by type (donut) | How customers pay |
| State slicer | Filters the whole page |

---

## Key insights

1. **Fast growth, then a plateau.** Monthly revenue climbed from about 0.1M in Jan 2017 to about 1.0M by Nov 2017 and held around 0.85–1.0M through 2018. The Nov 2017 peak lines up with Black Friday. Month-over-month growth started in triple digits and flattened toward 0% by mid-2018.
2. **Revenue is concentrated geographically.** São Paulo alone is roughly 38% of revenue; SP, RJ and MG together are about 63%.
3. **Category leaders differ by region.** Health & beauty, watches & gifts, bed/bath/table, sports & leisure and computers & accessories lead overall. By state, `bed_bath_table` tops SP and RS, `watches_gifts` tops RJ, PR, DF, GO and ES, and `health_beauty` tops MG, BA, PE, CE and PA.
4. **Quality risk where revenue is high.** `bed_bath_table` is the #3 category by revenue yet has the lowest review score of the top 10 (3.97, against 4.19 for `health_beauty`).
5. **Freight weighs hardest on remote states.** The ten most freight-heavy states are all in the North and Northeast (RR, MA, RO, AM, PI, SE, TO, AC, RN, PE), where freight is about 23–29% of item price.
6. **Delivery estimates are too conservative in remote states.** RR, AP and AM take 26–29 days on average, but arrive 17–20 days **ahead** of the estimated date.
7. **Credit card dominates payments.** About 78% of payment value is credit card (3.5 installments on average) and 18% is boleto, a one-off bank-slip payment common in Brazil. Vouchers and debit cards together are about 4%.

## Suggested actions

- **Investigate `bed_bath_table` quality** (seller- and product-level review drill-down): the largest revenue-at-risk category.
- **Reduce the freight burden in North/Northeast states** through regional fulfilment, carrier renegotiation or free-shipping thresholds, and measure the effect on conversion.
- **Recalibrate delivery estimates for remote states.** Promising dates closer to actual performance may improve conversion (a hypothesis to A/B test).
- **Plan promotions and inventory around the November peak**, and treat the flat 2018 growth as a signal to add retention levers (the RFM query in the SQL file is a starting point).

## Assumptions and limitations

- **Date window:** only Jan 2017 – Aug 2018 is analyzed. Late 2016 and Sep–Oct 2018 are incomplete in the source data. The SQL view does not trim dates; the trimming happens in Power Query, so the SQL results above include those tiny partial months.
- **Revenue vs. payments:** revenue is item price only; payment value also includes freight, hence 13.49M vs. 15.74M. AOV is (price + freight) / orders.
- **Review scores:** an order with items in several categories counts toward each of them (many-to-many), and Power BI averages review rows while the SQL averages per order item, so `bed_bath_table` reads 3.97 in Power BI vs. 3.90 in SQL.
- **Seasonality:** with about 20 months of data there is only one Black Friday and one full year. The calendar-month seasonality query in SQL is biased because Sep–Dec appear in fewer years than Jan–Aug.
- **No cost data:** profit and margin cannot be analyzed.
- **Delivery and RFM results** come from SQL; they are not on the dashboard.


## How to reproduce

1. Download the dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and put the CSVs in the folder reported by `SHOW VARIABLES LIKE 'secure_file_priv';`.
2. Clean the reviews file: `python scripts/clean_reviews.py olist_order_reviews_dataset.csv olist_order_reviews_dataset_clean.csv`
3. In MySQL Workbench run, in order: `olist_schema_mysql.sql` → `olist_load_data.sql` (edit the file paths) → `olist_analysis_queries.sql`.
4. Open the `.pbix` in Power BI Desktop, point the MySQL connection at `localhost:3306` / `olist_ecommerce`, and refresh.


## Future improvements

- Add pages for **delivery performance** and **RFM customer segments** (queries already written).
- Add a **next-quarter revenue forecast** per category.
- Bring in `geolocation` (deduplicated per zip prefix) for a state or city map.
- Refactor the SQL into **bronze / silver / gold layers** and wrap the load in a stored procedure for repeatable runs.

---

**Author:** Anurag Singh
