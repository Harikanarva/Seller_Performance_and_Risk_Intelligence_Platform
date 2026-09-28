# Seller Performance and Risk Intelligence Platform

An end-to-end analytics project that scores, tiers, and stress-tests marketplace sellers on the Olist Brazilian E-Commerce dataset, so a business can decide **who to promote, who to monitor, and who to warn or remove**.

**Stack:** MySQL · Python (pandas, mysql-connector-python) · Power BI

---

## Business Problem

Olist has no systematic way to identify underperforming sellers. Late deliveries, cancellations, and poor reviews are spread across thousands of sellers, and a small group can do outsized damage to customer satisfaction. Without a scorecard, decisions about search ranking, warnings, and delisting are made on gut feel.

This project answers three questions:

1. **Which sellers are hurting the platform?** (on-time delivery, reviews, cancellations)
2. **What action should be taken on each seller?** (Promote / Monitor / Warn-Remove)
3. **Is it worth acting?** How much of the negative-review problem sits with the bottom tier relative to its share of orders?

---

## Dashboard Preview


| Page | Preview |
|---|---|
| Scorecard Dashboard | `C:\Users\HP\Desktop\OneDrive\Pictures\Screenshots\Screenshot 2026-09-28 200256.png` |
| Seller Risk & Root Cause Analysis | `C:\Users\HP\Desktop\OneDrive\Pictures\Screenshots\Screenshot 2026-09-28 200421.png` |
| Decision Simulator | `C:\Users\HP\Desktop\OneDrive\Pictures\Screenshots\Screenshot 2026-09-28 200454.png` |

<img width="1330" height="737" alt="Screenshot 2026-09-28 200256" src="https://github.com/user-attachments/assets/e46ff97b-52ed-47f2-bac0-7bd833d3c285" />
<img width="1326" height="736" alt="Screenshot 2026-09-28 200421" src="https://github.com/user-attachments/assets/4331a37b-6d1c-4041-8641-fffded396290" />
<img width="1328" height="732" alt="Screenshot 2026-09-28 200454" src="https://github.com/user-attachments/assets/af92f27d-fcb7-49e4-baa7-949463c6c826" />



---

## Key Results

Portfolio-level metrics from the dashboard:

| Metric | Value |
|---|---|
| Sellers analysed | ~3K |
| Average on-time rate | 0.85 |
| Average review score | 3.97 |
| Average cancellation rate | 0.02 |

Seller tier distribution:

| Tier | Share of sellers |
|---|---|
| Promote | 7.85% |
| Monitor | 35.15% |
| Warn/Remove | 14.96% |
| Not Rated (low order volume) | 42.04% |

> "Flagged 463 high-risk sellers (14.96 \% of 3K sellers) representing 2.51M in high-risk revenue exposure (18.45 \% of total revenue), enabling targeted seller review and risk prioritization."

---

## Approach

### 1. Data cleaning and modelling (MySQL)
- Loaded the raw Olist tables (customers, orders, order items, reviews, products, sellers, category translation).
- Cleaned duplicates, nulls, inconsistent text, invalid dates, and orphan keys.
- Built a **star schema**: `fact_order_items` at order-item grain, with `dim_seller`, `dim_customer`, `dim_products`, `dim_date`, and a `dim_seller_scorecard` table for tier results.

### 2. Seller scorecard (SQL)
Per-seller metrics: order volume, on-time %, average review score, cancellation rate. On-time flags are `NULL` for undelivered orders so in-transit orders are not counted as late.

### 3. Tiering and validation (Python)
- Pulled the scorecard into pandas via `mysql-connector-python`.
- Flagged low-volume sellers as **Not Rated** instead of tiering them on too little data.
- Assigned Promote / Monitor / Warn-Remove tiers from the seller metrics. *(Describe your exact rule here: thresholds or weighted composite score.)*
- Validated tier sizes and spot-checked sellers against raw numbers.
- Calculated the disproportionate-impact statistic: bottom-tier share of orders vs share of 1-star reviews.

### 4. Dashboard (Power BI)
Three pages, with all tiering logic kept upstream and DAX used only for aggregation and interactivity.

| Page | Purpose |
|---|---|
| **Scorecard Dashboard** | Portfolio KPIs, tier donut, drill-through seller table |
| **Seller Risk & Root Cause Analysis** | Decomposition Tree and Key Drivers visuals to explain what drives at-risk sellers |
| **Decision Simulator** | What-if parameters for review score, on-time rate, and cancellation rate thresholds; at-risk seller counts recalculate in real time |

---

## Recommendations

| Tier | Recommended action |
|---|---|
| Promote | Boost in search ranking and featured placement |
| Monitor | Track monthly; escalate if metrics decline |
| Warn/Remove | Issue performance warning; delist if no improvement within a set window |
| Not Rated | Collect more order history before judging |

---

## Repository Structure

```
seller-performance-scorecard/
├── README.md
├── Seller_Performance_Scorecard.pbix
├── screenshots/
├── sql/          # cleaning, star schema, seller_scorecard view
└── python/       # tiering and validation script
```

---

## How to Run

1. Download the [Olist dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and load the CSVs into MySQL as `raw_*` tables.
2. Run the SQL scripts in order: cleaning → star schema → `seller_scorecard` view.
3. Run the Python script to tier sellers and export the scored table.
4. Open `Seller_Performance_Scorecard.pbix` in Power BI Desktop and refresh the data source.

---

## Limitations

- Tiers are relative to the platform's own seller population, not an absolute quality standard.
- Sellers with low order volume are left unrated, so a large share of sellers is not scored.
- The dataset covers 2016–2018 and may not reflect current marketplace behaviour.

---

## Author

**Harika** — Computer Science Engineering graduate (2026), aspiring data analyst.
GitHub: [Harikanarva](https://github.com/Harikanarva)
