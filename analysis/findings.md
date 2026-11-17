# Findings

This document records the results of the analyses in this folder and how far each result can be taken. A section is added as each analysis is completed.

## How to read this document

* **Observation:** what the query output directly shows.
* **Inference:** what can reasonably be concluded from the observations, with the reasoning stated.
* **Hypothesis:** a possible explanation that has not been tested or confirmed.
* **Uncertainty:** what the available data cannot settle.
* **Needs additional data:** questions that cannot be answered with this dataset.

All results come from `DataWarehouse_Test`, the database rebuilt from the corrected source files (decisions 6 and 7 in [`docs/decisions.md`](../docs/decisions.md)). Revenue is the sum of `sales_amount`; the source does not state a currency. The analysis conventions (main window 2011–2013, order-level dating, treatment of undated orders) are defined in decision 7.

---

## Q1. How have revenue, units and orders changed over time?

Source: [`01_revenue_trends.sql`](01_revenue_trends.sql). Every section reconciles to the control totals of the fact table (60,398 lines, 27,659 orders, revenue 29,356,250).

| Year | Orders | Lines | Units | Revenue | AOV |
|---|---|---|---|---|---|
| 2011 | 2,216 | 2,216 | 2,216 | 7,075,088 | 3,192.73 |
| 2012 | 3,269 | 3,397 | 3,397 | 5,842,231 | 1,787.16 |
| 2013 | 21,287 | 52,798 | 52,823 | 16,349,836 | 768.07 |

AOV (average order value) is revenue divided by orders.

### Observations

1. **Orders and revenue diverge.**
   * 2011 to 2012: orders increased by 47.5% while revenue decreased by 17.4%. AOV fell by 44.0%.
   * 2012 to 2013: orders increased by 551.2% and revenue increased by 179.9%. AOV fell by 57.0%.
   * Orders genuinely increased in both transitions, but revenue did not grow at the same rate, because AOV declined. The cause of the decline in AOV is not known.
2. **AOV changes in steps.**
   * It falls from about 3,015 in December 2011 to about 1,966 in January 2012. Across the twelve months of 2012 it ranges from about 1,660 to about 1,966.
   * It falls again from about 1,759 in December 2012 to about 1,357 in January 2013 and about 543 in February 2013. From March to December 2013 it ranges from about 621 to about 855.
3. **The relationship between lines and orders changes in December 2012.**
   * In every month up to November 2012, the number of lines equals the number of orders.
   * December 2012 is the first month with more lines than orders (483 lines, 355 orders).
   * Lines per order are 1.00 in 2011, 1.04 in 2012 and 2.48 in 2013 (52,798 lines in 21,287 orders).
   * In this dataset, units and lines track each other closely: 2,216 units for 2,216 lines in 2011, 3,397 for 3,397 in 2012, and 52,823 units for 52,798 lines in 2013. This is specific to this dataset. It should not be read as a general rule that more lines per order means more units per order.
   * The relationship between lines and orders does not, by itself, explain the decline in AOV.
4. **January 2014 is incomplete and not comparable with full months or years.** It covers only 1–28 January, which is why it is kept out of annual comparisons and treated as context. It has 871 orders, 1,970 lines, revenue of 45,642 and an AOV of 52.40. Monthly revenue in 2013 never fell below 771,218, and monthly AOV never fell below 543.
   * Its short duration does not, by itself, explain the low AOV. AOV measures revenue relative to the number of orders, and the unusually low value remains unexplained.
5. **Seasonal shares vary across years.**
   * June holds a relatively high share of the year's revenue in all three years: 10.4% in 2011, 9.5% in 2012 and 10.0% in 2013.
   * The last quarter holds 28.8% of the year's revenue in 2011, 29.1% in 2012 and 32.6% in 2013.
   * January and February differ across years: 6.6% and 6.6% in 2011, 8.5% and 8.7% in 2012, 5.2% and 4.7% in 2013.
   * In 2013, monthly orders rise from 632 in January to 2,192 in December.
   * Three complete years, with structural differences between them, are not enough to establish a stable seasonal pattern.
6. **Undated orders are negligible and accounted for.** Two orders have no usable date: 3 lines and revenue of 34 (decision 7.2).
7. **2013 weighs heavily in the whole-period totals.** It accounts for 77.0% of orders, 87.4% of lines and 55.7% of revenue.

### Arithmetic decomposition (descriptive only)

The change in revenue between two years can be split exactly into an effect of the change in the number of orders and an effect of the change in AOV:

| Transition | Revenue change | Effect of more orders | Effect of higher AOV |
|---|---:|---:|---:|
| 2011 to 2012 | −1,232,857 | +3,361,944 | −4,594,801 |
| 2012 to 2013 | +10,507,605 | +32,201,076 | −21,693,471 |

This is a mathematical breakdown of the revenue change, not a causal explanation. It describes the size of each component, not why orders or AOV changed.

### Inferences

* In this dataset, the number of orders is not a reliable stand-in for revenue, because the two metrics moved at very different rates in both transitions.
* The step changes in AOV and the change in the relationship between lines and orders occurred within the period from December 2011 to February 2013. Their causes remain unknown and warrant further investigation.

### Hypothesis (not established)

* Changes in the product mix (what is sold, and in which combinations) may explain part of the decline in AOV and of the change in order structure. This was not tested in Q1. Q2 investigates it by comparing category shares by year, revenue per line, and each category's contribution to the year-over-year changes in lines and revenue (see Q2).
* Price changes, and changes in how the dataset itself was produced, are other possible explanations. They are not established causes and cannot be ruled out with this data.

### Uncertainty

* The causes of the changes in AOV and in order structure.
* The cause of the unusually low AOV in January 2014.
* Whether a stable seasonal pattern exists, given the limited number of complete years and the effect of within-year growth, especially in 2013.

### Needs additional data

* List prices, discounts and price history. Realized price per sale is available (see Q2); what is missing is the information needed to tell a list-price change from a discount.
* Information about how the data was generated or extracted, to investigate the step changes and the January 2014 values.
* More complete years, to assess seasonality.

### Implications for later analyses

* Full-period aggregates remain valid descriptions of the dataset. Because 2013 accounts for most orders and lines and a large share of revenue, aggregate results are strongly shaped by 2013 and should be interpreted alongside year-level comparisons.

---

## Q2. Does product mix help explain the decline in AOV?

Source: [`02_product_mix.sql`](02_product_mix.sql), output in [`output/02_product_mix.txt`](output/02_product_mix.txt). Sections are cited by letter. Section J (all `OK`: 60,398 lines, 27,659 orders, revenue 29,356,250, units 60,423) checks overall totals by period, category, subcategory, category × year lines (main window) and order class. It does not check the figures of the printed sections one by one. Section I covers only products sold in consecutive years, by design. Order classes are defined in [decision 7.8](../docs/decisions.md#78-order-classes-by-product-category). No price–mix decomposition was done. The splits shown are the additive category split of the year-over-year changes (section D) and a counterfactual that separates the shift across Bike subcategories from the change within them, 2012 to 2013 (Inferences, fourth item); neither separates price from mix. Section I is a simple like-for-like comparison.

AOV = lines per order × revenue per line (section A1):

| Year | Lines | Orders | Lines per order | Revenue per line | AOV | Bike lines, % of lines |
|---|---|---|---|---|---|---|
| 2011 | 2,216 | 2,216 | 1.00 | 3,192.73 | 3,192.73 | 100.0 |
| 2012 | 3,397 | 3,269 | 1.04 | 1,719.82 | 1,787.16 | 96.2 |
| 2013 | 52,798 | 21,287 | 2.48 | 309.67 | 768.07 | 18.4 |

Revenue per line fell by 46.1% from 2011 to 2012 (1,719.82 / 3,192.73 = 0.539) and by 82.0% from 2012 to 2013 (309.67 / 1,719.82 = 0.180).

### Observations

1. **The products sold change a lot between years (sections B, C, D).** The dimension has Bikes, Accessories and Clothing (all with sales), plus Components (127 products, no sales) and 7 products with no category (section B).

   | Year | Bikes lines | Accessories lines | Clothing lines | Bikes % of revenue |
   |---|---|---|---|---|
   | 2011 | 2,216 (100.0%) | 0 | 0 | 100.0 |
   | 2012 | 3,269 (96.2%) | 106 (3.1%) | 22 (0.6%) | 100.0 |
   | 2013 | 9,706 (18.4%) | 34,406 (65.2%) | 8,686 (16.5%) | 93.9 |

   Revenue per line in 2013: Bikes 1,582.35, Accessories 19.41, Clothing 37.27.
2. **Contribution to the year-over-year changes (section D).**
   * 2011 to 2012: lines +1,181 (Bikes 89.2%, Accessories 9.0%, Clothing 1.9%). Revenue −1,232,857, of which Bikes −1,235,645 (100.2%).
   * 2012 to 2013: lines +49,401 (Accessories 69.4%, Clothing 17.5%, Bikes 13.0%). Revenue +10,507,605 (Bikes 90.6%, Accessories 6.3%, Clothing 3.1%).
3. **Accessories and Clothing first appear in December 2012, the month lines first exceed orders (sections A2, G2, G3, G4; A2 starts in January 2011).**
   * First month with sales: Bikes December 2010 (context tail), Accessories and Clothing December 2012 (106 and 22 lines; 19 and 11 products).
   * Non-Bike share of lines: 26.5% in December 2012, 70.1% in January 2013, 86.9% in February 2013. AOV in the same months: 1,759.03, 1,357.21, 542.73.
   * Average unit price of Bikes in January to April 2013: 1,669.70, 1,550.08, 1,591.60, 1,604.02 (November 2012, when every line was a Bike: average Bike unit price 1,660.24, equal to AOV).
   * Products first sold: 49 in December 2012 (19 Bikes, 19 Accessories, 11 Clothing) and 37 in January 2013 (25, 3, 9).
4. **The January 2012 step happens inside Bikes (sections A2, G3, G4).** From December 2011 to January 2012 AOV goes from 3,015.29 to 1,965.73 and every line in both months is a Bike (non-Bike share 0.0%); the average Bike unit price equals AOV in those months. Bike products first sold: 12 in December 2011 and 6 in January 2012.
5. **Order composition (section H).**

   | Order class, 2013 | Orders | % of orders | AOV | Lines per order | % of revenue |
   |---|---|---|---|---|---|
   | Bikes only | 1,205 | 5.7 | 1,533.34 | 1.00 | 11.3 |
   | Bikes + other | 8,501 | 39.9 | 1,636.95 | 3.03 | 85.1 |
   | No bikes | 11,581 | 54.4 | 50.64 | 2.23 | 3.6 |

   In 2012, 3,207 orders (98.1%) are Bikes only with AOV 1,787.33, and 62 (1.9%) are Bikes + other with AOV 1,778.53 (3.06 lines per order). In 2011 all 2,216 orders are Bikes only. Orders containing a Bike in 2013: 8,501 + 1,205 = 9,706, with revenue 13,915,719 + 1,847,679 = 15,763,398, so their AOV is 15,763,398 / 9,706 = 1,624.09, against 768.07 for all orders.
6. **Within Bikes, revenue per line fell in Road Bikes and Mountain Bikes (section E2).** Road Bikes 3,153.61 (2011), 1,647.31 (2012), 1,273.37 (2013); Mountain Bikes 3,373.08, 2,061.15, 1,825.97. Touring Bikes went the other way, but from a tiny base: 1,645.38 in 2012 (13 lines) and 1,774.93 in 2013 (2,154 lines). Average Bike unit price (section C): 3,192.73, 1,786.31, 1,582.35, i.e. −44.1% (1,786.31 / 3,192.73 = 0.559) and −11.4% (1,582.35 / 1,786.31 = 0.886).
7. **Like-for-like realized prices of products sold in consecutive years (section I).**

   | Transition | Category | Products in both years (of those sold in the later year) | % of category revenue, later year | Lower / same / higher | Median change | Price index |
   |---|---|---|---|---|---|---|
   | 2011 to 2012 | Bikes | 24 (of 50) | 70.7 | 0 / 5 / 19 | +5.8% | +1.3% |
   | 2012 to 2013 | Bikes | 35 (of 60) | 81.5 | 0 / 19 / 16 | 0.0% | +7.7% |
   | 2012 to 2013 | Accessories | 19 (of 22) | 90.4 | 0 / 19 / 0 | 0.0% | 0.0% |
   | 2012 to 2013 | Clothing | 11 (of 20) | 52.1 | 0 / 11 / 0 | 0.0% | 0.0% |

   No product in these groups was sold at a lower unit price than in the previous year. The price index values the later year's units at the earlier year's prices.
8. **Assortment (sections G1, I).** Bike products sold: 37 (2011), 50 (2012), 60 (2013). Of the 50 in 2012, 26 are new (29.3% of that year's Bike revenue, section G1) and 24 were also sold in 2011 (section I), so 37 − 24 = 13 products of 2011 were not sold in 2012. In 2013, 25 of 60 Bike products are new (18.5% of Bike revenue).

### Inferences

* **2012 to 2013: the AOV decline coincides with a large shift in product mix.** Accessories and Clothing, with revenue per line of 19.41 and 37.27, are 81.6% of 2013 lines ((34,406 + 8,686) / 52,798), and 54.4% of 2013 orders contain no Bike (AOV 50.64). They appear in December 2012, the first month in section A2 (from January 2011) in which lines exceed orders, immediately before the second AOV step (1,759.03 in December 2012 to 1,357.21 in January 2013, section A2). In December 2012 the new items are add-ons to orders that already contain a Bike (all 355 orders contain one: section H shows no 2012 order without a Bike; 128 non-Bike lines, 483 − 355, section A2), and AOV rises from 1,660.24 in November to 1,759.03, mostly through the average Bike unit price (1,660.24 to 1,751.17, section G3); the add-ons add 7.86 per order (1,759.03 − 1,751.17). The fall starts in January 2013, when at least 135 orders have no Bike (632 orders − 497 Bike lines, section G3), and at least 967 in February (1,421 − 454). In these months the AOV fall coincides with orders that contain no Bike, not with low-priced items added to Bike orders. Average Bike unit price also fell from December 2012 to January 2013 (1,751.17 to 1,669.70, section G3), so the order mix is not the only factor in that step. No decomposition was done, so the share of the decline due to the mix is not measured. This describes the composition of the data; it does not show why they entered.
* **The category mix does not explain all of the decline.** Orders that contain a Bike have an AOV of 1,624.09 in 2013, 9.1% below the 2012 AOV of 1,787.16 (1,624.09 / 1,787.16 = 0.909). Bikes + other is 1.9% of 2012 orders and 39.9% of 2013 orders (section H), so the two years' Bike orders are not like for like, and this only indicates that a decline remains. What remains may itself include product mix within Bikes (fourth item).
* **2011 to 2012: not a category-mix effect.** Lines are 96.2% to 100% Bikes, and the AOV of Bikes-only orders fell to 1,787.33. It is also not a price cut on products sold in both years: none of the 24 was sold at a lower price, and their price index is +1.3%. The average Bike unit price fell 44.1% while continuing products did not get cheaper, so the fall comes from the product mix within Bikes. The output does not split that mix effect into its two possible parts: products entering and leaving (13 of the 37 products of 2011 were not sold in 2012; 26 of the 50 sold in 2012 are new, with 29.3% of that year's Bike revenue (of the 26, 6 were first sold in January 2012, 1 in February and 19 in December 2012, section G4); 18 Bike products were first sold in December 2011 and January 2012, around the step), and volume moving toward cheaper continuing products, which the price index holds fixed because it uses the later year's units as weights.
* **2012 to 2013 within Bikes.** The like-for-like price index is +7.7% while the average Bike unit price fell 11.4%, so the fall is not a lower price of the same products. It comes from within the subcategories, not from the shift between them. The shift raises the Bike average under either weighting, and the within-subcategory change is larger than the total fall (−203.96 = 1,582.35 − 1,786.31). At 2012 subcategory revenue per line and 2013 line counts, the Bike average would be 1,794.92 ((4,080 × 1,647.31 + 3,472 × 2,061.15 + 2,154 × 1,645.38) / 9,706, derived from E2): shift +8.61 (1,794.92 − 1,786.31), within −212.57 (1,582.35 − 1,794.92). At 2013 revenue per line and 2012 line counts it would be 1,460.97 ((2,158 × 1,273.37 + 1,098 × 1,825.97 + 13 × 1,774.93) / 3,269): shift +121.38 (1,582.35 − 1,460.97), within −325.34 (1,460.97 − 1,786.31). The size of the shift depends on the weights; its direction does not. Volume moved mainly from Road Bikes to Touring Bikes (Road 66.0% to 42.0% of Bike lines, 2,158 / 3,269 and 4,080 / 9,706; Touring 0.4% to 22.2%, 13 / 3,269 and 2,154 / 9,706), which had about the same 2012 revenue per line (1,647.31 against 1,645.38, the latter on 13 lines); Mountain Bikes rose from 33.6% to 35.8% (1,098 / 3,269; 3,472 / 9,706). Within the subcategories, revenue per line fell 22.7% in Road Bikes (1,647.31 to 1,273.37; 1,273.37 / 1,647.31 = 0.773) and 11.4% in Mountain Bikes (2,061.15 to 1,825.97; 0.886) (section E2). Touring Bikes (1,774.93 in 2013) are above the 2013 Bike average of 1,582.35 and so raise it. Which Road and Mountain products drive the fall was not analyzed.

### Hypotheses (not established)

* How much of the 2012 fall within Bikes comes from new models replacing dearer ones and how much from volume shifting among continuing models. Not tested: this analysis does not compare the price level of the 13 products that left with the 26 that entered, nor the volume shares of the 24 continuing products between the two years.
* The simultaneous appearance of 49 products and two new categories in December 2012 may reflect how the dataset was produced, or a business launch, rather than a gradual change. Products also first appear in a cluster in December 2011 and January 2012 (12 and 6, section G4), so the step from December 2011 to January 2012 may share the same origin. Cannot be tested with this data.
* Discounting or a list-price change may sit behind realized prices. Cannot be separated here.

### Uncertainty

* How much of the AOV decline each factor accounts for. No price–mix or AOV decomposition was done, so mix, price and order structure are described, not apportioned. The additive category split of section D apportions the changes by category, not by factor, and the counterfactual in Inferences (fourth item) separates the shift across Bike subcategories from the change within them, 2012 to 2013.
* Product attributes are the current product version; a product's category could differ historically.
* Section I covers only products sold in two consecutive years, uses realized prices, and says nothing about entering or exiting products.
* 2011 and 2012 have few lines (2,216 and 3,397) against 52,798 in 2013; their shares and medians are less stable. 2013 itself changes within the year (Bike share of lines 29.9% in January 2013, 13.1% in February and 14.9% in March, section A2).
* Country mix is not examined and could contribute. Customer overlap between Bike orders and No bikes orders is answered in Q3 (Observation 9): no customer has both.
* The 2011 to 2012 reading uses annual averages and an annual price index. The monthly step from December 2011 to January 2012 (3,015.29 to 1,965.73, section A2; −34.8%, 1,965.73 / 3,015.29 = 0.652) was not decomposed at monthly grain, so which products drive it is unknown.
* "Product" means a distinct `product_number`. A relaunch under a new number would count as one product leaving and another entering, so new and exited products (sections G1, I) may overstate real assortment changes.

### Needs additional data

* List prices, discounts and price history, to separate price changes from discounting.
* Information on how the data was generated or extracted, to interpret the abrupt appearance of products and categories in December 2012 and the step in December 2011 to January 2012.
* A product-level price–mix decomposition (not done here) if the question of price against composition within Bikes must be answered.

---

## Q3. Do customers place a second order, how quickly, and who buys the 2013 No bikes orders?

Source: [`03_repeat_purchasing.sql`](03_repeat_purchasing.sql), output in [`output/03_repeat_purchasing.txt`](output/03_repeat_purchasing.txt). Sections are cited by letter. Section G reconciles to the control totals (all `OK`: 60,398 lines, 27,659 orders, revenue 29,356,250, units 60,423, 18,484 customers) and section F has no unclassified orders. The rules (eligibility, same-day orders, January 2014 follow-up, minimum group size of 100 eligible customers, ties) are [decision 7.9](../docs/decisions.md#79-repeat-purchase-sequence-rules); order classes are [decision 7.8](../docs/decisions.md#78-order-classes-by-product-category). Inside the script customers are grouped by `customer_key`. Inside one query `customer_key` is the `ROW_NUMBER()` over `cst_id` of `gold.dim_customers` (decision 2), so it is one-to-one with `customer_id`; section G shows 18,484 of each. A second order is the customer's second distinct order; "within N days" counts customers whose first order is at least N days before the end of the data (2014-01-28).

| Cohort (year of first order) | Customers | Dated orders | Customers with 2+ orders |
|---|---|---|---|
| 2011 | 2,216 | 4,624 | 1,955 |
| 2012 | 3,225 | 6,793 | 2,955 |
| 2013 | 12,521 | 15,697 | 1,935 |
| Context: first order in the 2010 tail / January 2014 | 14 / 506 | 30 / 513 | 13 / 7 |
| No dated order | 2 | 0 | 0 |
| Total | 18,484 | 27,657 (+2 undated orders) | 6,865 |

(Section A. The 6,865 customers with two or more orders match decision 7.6 and are descriptive context only. Orders per customer, 2.09, 2.11 and 1.25 for the three cohorts, depend on how long each cohort is observed and are not compared.)

### Observations

1. **Second orders within N days, by cohort (section B1; rate shown with eligible customers).**

   | Cohort | 90 days | 180 days | 365 days |
   |---|---|---|---|
   | 2011 | 0 of 2,216 (0.0%) | 0 of 2,216 (0.0%) | 0 of 2,216 (0.0%) |
   | 2012 | 47 of 3,225 (1.5%) | 209 of 3,225 (6.5%) | 1,451 of 3,225 (45.0%) |
   | 2013 | 844 of 10,211 (8.3%) | 1,133 of 7,048 (16.1%) | 29 of 216 (13.4%) |

   The columns of the 2013 row use different eligible customers (10,211, 7,048 and 216), so they are not compared across windows.

   At 365 days the 2013 cohort covers only first orders from 2013-01-01 to 2013-01-28 (216 customers, section C2). Same-day second orders are 0 in the 2011 and 2012 cohorts and 7 (90 days) and 6 (180 days) in the 2013 cohort; excluding them the 2013 rates are 8.2% and 16.0%.
2. **For the 2011 to 2013 cohorts, no second order occurs before the fourth quarter of 2012 (section B2).** The earliest quarter with a second order is the fourth quarter of 2012 (30 second orders from the 2011 cohort and 14 from the 2012 cohort). Second orders by quarter from the fourth quarter of 2012 to the fourth quarter of 2013: 2011 cohort 30, 546, 449, 490, 440; 2012 cohort 14, 392, 789, 853, 907; 2013 cohort (no second order before 2013) 127, 362, 537, 703 from the first to the fourth quarter of 2013, plus 206 in January 2014. The totals by cohort (1,955, 2,955 and 1,935) equal the customers with 2+ orders in section A.
3. **Time to second order (section C1; customers eligible for 365 days who reordered within 365 days).** 2012 cohort: 1,451 customers, median 293.0 days; by band 0 days 0, 1 to 30 days 4, 31 to 90 days 43, 91 to 180 days 162, 181 to 365 days 1,242 (85.6%). 2013 cohort: 216 eligible, 29 reordered; bands 0, 4, 3, 10, 12 (counts only). 2011 cohort: no customer reordered within 365 days.
4. **January 2014 follow-up changes little (section B3, 90 days, 2013 cohort).** With the end of the data at 2013-12-31: 786 of 9,196 (8.5%). With January 2014 follow-up: 844 of 10,211 (8.3%). The 2012 cohort is the same in both (47 of 3,225).
5. **Second order by class of the first order (section D1; customers whose first order is on or after 2012-12-01).**

   | First-order class | 90 days | 180 days |
   |---|---|---|
   | Bikes + other | 12 of 2,440 (0.5%) | 55 of 1,587 (3.5%) |
   | Bikes only | 26 of 582 (4.5%) | 58 of 488 (11.9%) |
   | No bikes | 831 of 7,500 (11.1%) | 1,072 of 5,284 (20.3%) |

   Excluding the 8 customers with more than one order on their first date (all in the 2013 cohort, section A; 7 of them are eligible at 90 days and 6 at 180 days) changes only the No bikes rows: 824 of 7,493 (11.0%) and 1,066 of 5,278 (20.2%). Same-day second orders are 7 (90 days) and 6 (180 days), all in the No bikes class.
6. **The No bikes second-order rate at 90 days differs by quarter of the first order (section D2).** 13.7% (1,989 eligible, first quarter of 2013), 10.9% (2,467), 9.9% (2,310), 8.4% (734, fourth quarter; first orders from 1 to 30 October only, because eligibility ends at 2013-10-30).
7. **Second orders do not cross between Bike and No bikes customers; among Bike customers the class changes in 55 cases (section E, 180 days).** Bikes + other (1,587 eligible): no second order 1,532 (96.5%), Bikes + other 50 (3.2%), Bikes only 5 (0.3%). Bikes only (488): none 430 (88.1%), Bikes + other 50 (10.2%), Bikes only 8 (1.6%). No bikes (5,284): none 4,212 (79.7%), No bikes 1,072 (20.3%). Within 180 days no customer has a second order of the No bikes class after a first order with a Bike, or the reverse (for any date see observation 9, section F2). Excluding ties: No bikes 5,278 eligible, 4,212 (79.8%) and 1,066 (20.2%).
8. **The 2013 No bikes orders (section F1).** Of the 11,581:

   | Position in the customer's sequence | Orders | % of orders | Distinct customers |
   |---|---|---|---|
   | a. first order of the customer | 8,844 | 76.4 | 8,844 |
   | b. later order, same date as the first order | 8 | 0.1 | 8 |
   | c. later date, Bike in an earlier-dated order | 0 | 0.0 | 0 |
   | d. later date, no earlier Bike, Bike on the same date | 0 | 0.0 | 0 |
   | e. later date, no Bike earlier or on the same date | 2,729 | 23.6 | 1,643 |
   | Total | 11,581 | 100.0 | 8,844 |

   Shares are of orders (8,844 + 8 + 2,729 = 11,581). The 8,844 distinct customers of the total equal the 8,844 first orders in row a.
9. **Customers who bought a Bike and customers with No bikes orders do not overlap (section F2).** 8,844 customers placed a No bikes order in 2013 and none of them had a Bike in an order dated before 2013; 5,455 customers had a Bike in an order dated before 2013 and none placed a No bikes order in 2013. At any date: 9,132 customers have at least one Bike order, none of them also a No bikes order; 9,352 have at least one No bikes order, none of them also a Bike order (9,132 + 9,352 = 18,484).

### Inferences

* **For the sequence of orders, the idea that the 2013 No bikes orders are later orders of customers with an earlier Bike is not supported.** None of the 11,581 No bikes orders of 2013 is a later order of a customer with an earlier Bike (rows c and d are 0). Because the 8,844 distinct customers equal the 8,844 first orders in row a, every customer with a 2013 No bikes order has a 2013 No bikes order as their first order in the data; 76.4% of these orders are those first orders and 23.6% (plus 8 same-day orders) are later orders of the same customers. Within this data the two kinds of order come from two separate groups of customers (observation 9).
* **The 2011 cohort's 0% and the 2012 cohort's 45.0% at 365 days coincide with second orders not occurring before the fourth quarter of 2012 (observation 2).** Rates by cohort in section B are therefore not read as cohort effects. The output cannot tell calendar time from how the data was produced. The median days and the band shares in section C also depend on calendar time, since no second order occurs before the fourth quarter of 2012 for these cohorts, so they are not read as the speed of reordering.
* **Customers whose first order has no Bike reorder more often than those whose first order has a Bike (observation 5), but the data cannot separate the class from the group of customers or from the period.** First-order class coincides with the customer group (observation 9), and the No bikes rate at 90 days differs by quarter of the first order (observation 6). The comparison of classes is therefore descriptive.
* **At 90 days in the 2013 cohort (section B3) the rate is 8.3% with and 8.5% without January 2014 follow-up, and at most 7 customers per rate are same-day.**

### Hypotheses (not established)

* Customers with No bikes orders may be a population defined by what they buy (accessories, clothing), and their reorders may reflect that product type. Not tested: nothing in this analysis looks at what they buy.
* The complete separation of the two customer groups may reflect how the dataset was produced rather than behaviour. Cannot be tested with this data.

### Uncertainty

* Customers are observed from 2010-12-29. "First order" means first order in the data; a customer may have bought earlier, especially in the 2011 cohort, in a direction that cannot be checked.
* The 365-day figure of the 2013 cohort covers 216 customers whose first order is in January 2013, of whom 29 reordered; its band shares are based on 29 customers and are not interpreted.
* The January 2014 sensitivity (B3) covers only 90 days by cohort, with different eligible populations in the two variants (9,196 and 10,211); the 180- and 365-day results and sections D and E have no such sensitivity.
* Bikes only first orders include a large share from December 2012: 286 of 582 eligible at 90 days (49.1%) and 52 of the 58 reorders at 180 days (89.7%), section D2. So their rates and class transitions mix class with calendar and are not read as a class pattern.
* Ties on the first date are broken by `order_number`, which is arbitrary; they affect 8 customers (observation 5) and change the No bikes rates by at most 0.1 point.
* Whether the same-day second orders (7 and 6 customers) are real repeat purchases or split baskets cannot be told.
* The results describe the order sequence of customers as identified in the data. A person with two customer records would appear as two customers.

### Needs additional data

* Customer history before 2010-12-29, to tell first orders in the data from first orders ever.
* Information on how the data was generated, to interpret the complete separation of the two customer groups and the absence of second orders before the fourth quarter of 2012.
* Customer identity resolution, if one person can hold several customer records.
* What the No bikes customers buy and why they reorder, which needs product-level analysis not done here.

---

## Q4. How concentrated is revenue: what share of revenue is accounted for by the highest-revenue customers and products?

Source: [`04_revenue_concentration.sql`](04_revenue_concentration.sql), output in [`output/04_revenue_concentration.txt`](output/04_revenue_concentration.txt), plan in [`04_plan.md`](04_plan.md). Sections are cited by letter. Section G reconciles to the control totals (all 29 checks `OK`: 60,398 lines, 27,659 orders, revenue 29,356,250, units 60,423, 18,484 customers; revenue by year, by customer group, by product and by category equals 7,075,088 / 5,842,231 / 16,349,836 for 2011 / 2012 / 2013; 9,132 Bike customers + 9,352 No bikes customers = 18,484, and no customer has both a Bike order and a No bikes order). The customer groups are [decision 7.10](../docs/decisions.md#710-customer-groups-by-bike-purchase). The minimum sizes (a customer statistic is interpreted only with at least 100 active customers and a top group of at least 30) are specific to Q4 and are declared in the plan, not in decision 7. Inside the script customers are grouped by `customer_key` and never reported.

Reading rules used below. A **top p% group** is the k = CEILING(p × N) highest-revenue active customers of the year (N = active customers). **Equal-distribution reference:** if every active customer had the same revenue, a top p% group would hold p% of revenue. A product cut is the n highest-revenue products, and n of N products would hold n / N of revenue under an equal distribution. N is shown next to every share. The "interpretable" flag of the output checks only the sizes (N and k); it does not mean that a figure says something about customers (see Inferences 1).

### Observations

1. **Active customers and revenue per customer by year (section A).**

   | Year | Active customers | Revenue | Mean | Median | P90 | P99 | Max | Mean / median |
   |---|---|---|---|---|---|---|---|---|
   | 2011 | 2,216 | 7,075,088 | 3,192.73 | 3,578.00 | 3,578.00 | 3,578.00 | 3,578 | 0.89 |
   | 2012 | 3,255 | 5,842,231 | 1,794.85 | 2,071.00 | 2,443.00 | 2,443.00 | 4,985 | 0.87 |
   | 2013 | 17,427 | 16,349,836 | 938.19 | 243.00 | 2,443.00 | 4,805.00 | 10,865 | 3.86 |

   In 2011 all 2,216 customers have one order (revenue 7,075,088). In 2012, 3,241 customers have one order (5,791,711) and 14 have two (50,520). In 2013, 14,762 customers have one order (11,840,518), 2,191 have two (3,904,917) and 474 have three or more (604,401). Customers with two or more orders in 2013 are 2,191 + 474 = 2,665 (15.3% of 17,427) and account for 3,904,917 + 604,401 = 4,509,318, which is 27.6% of 16,349,836 (4,509,318 / 16,349,836 = 0.2758). The other 14,762 customers (84.7%) account for 11,840,518 (72.4%).

2. **Ties and the group rule in 2011 and 2012 (section D).** In 2011, 1,544 customers have the same revenue, so they tie at the boundary of every cut. That revenue is the maximum of section A, 3,578: 1,544 × 3,578 = 5,524,432, which is 78.08% of 7,075,088, the tie-inclusive share in D. The five largest products of 2011 sold 335 + 334 + 301 + 294 + 280 = 1,544 units, each at 3,578 (section E3: 1,198,630 / 335 = 3,578), for revenue 5,524,432 (E2) (the output does not link these customers to these products). The top 1% (23 customers) holds 1.16% under CEILING and 78.08% when the group includes every customer tied with the 23rd (k = 23, below the minimum; shown only for the tie effect). In 2012, 431 customers tie at the boundary of the 1%, 5% and 10% cuts and 749 at the 20% cut; the top 1% (33 customers) holds 1.67% under CEILING and 19.23% tie-inclusive (453 customers), and the top 20% (651 customers) holds 26.70% against 48.25% (1,228 customers).

3. **Customer concentration, all customers (section B; context, see Inferences 1 and 2).** Each cell gives the top group (k customers) and its share of the year's revenue.

   | Year | Active customers (N) | Top 1% | Top 5% | Top 10% | Top 20% |
   |---|---|---|---|---|---|
   | 2011 (context; see Inference 1) | 2,216 | 23: 1.2% (not interpreted: k < 30) | 111: 5.6% | 222: 11.2% | 444: 22.5% |
   | 2012 (context; see Inference 1) | 3,255 | 33: 1.7% | 163: 7.1% | 326: 13.9% | 651: 26.7% |
   | 2013 | 17,427 | 175: 6.1% | 872: 24.1% | 1,743: 37.5% | 3,486: 62.9% |
   | Equal-distribution reference | | 1% | 5% | 10% | 20% |

4. **The two customer groups in 2013 (section C1).** Bike customers are 8,583 of 17,427 active customers (49.3%) and account for 15,763,398 of 16,349,836 (96.4%). No bikes customers are 8,844 (50.7%) and account for 586,438 (3.6%); 8,583 + 8,844 = 17,427. In 2011 and 2012 all active customers are Bike customers (the No bikes group has 0 active customers).

   | 2013 | Active customers | Revenue | Mean | P10 | Median | P90 | P99 | Max | Mean / median |
   |---|---|---|---|---|---|---|---|---|---|
   | Bike customers | 8,583 | 15,763,398 | 1,836.58 | 571.00 | 1,736.00 | 3,096.60 | 4,860.00 | 10,865 | 1.06 |
   | No bikes customers | 8,844 | 586,438 | 66.31 | 7.00 | 50.00 | 129.00 | 276.00 | 1,537 | 1.33 |

   The median revenue of Bike customers (1,736) is above the largest revenue of any No bikes customer (1,537), so at least half of the 8,583 Bike customers, at least 4,292, have more revenue than every No bikes customer. The top 20% of all 2013 customers is 3,486 customers (section B), fewer than 4,292, so every top group of all customers in 2013 (1%, 5%, 10%, 20%) contains only Bike customers.

5. **Top shares inside each group in 2013 (section C2).** The denominator is the group's own revenue. All eight figures are above the minimum sizes (N ≥ 100, k ≥ 30).

   | 2013, group | Active customers (N) | Top 1% | Top 5% | Top 10% | Top 20% |
   |---|---|---|---|---|---|
   | Bike customers | 8,583 | 86: 3.6% | 430: 14.0% | 859: 24.7% | 1,717: 38.5% |
   | No bikes customers | 8,844 | 89: 8.6% | 443: 20.9% | 885: 31.8% | 1,769: 48.4% |
   | Equal-distribution reference | | 1% | 5% | 10% | 20% |

   The No bikes group holds a larger share than the Bike group at every cut (8.6 against 3.6, 20.9 against 14.0, 31.8 against 24.7, 48.4 against 38.5). At the 20% cut the shares are 38.5 / 20 = 1.9 and 48.4 / 20 = 2.4 times the reference; at the 1% cut they are 3.6 and 8.6 times.

6. **Sensitivity to the group rule in 2013 (section D).** Among the eight group rows (two groups, four cuts), the tie-inclusive share exceeds the CEILING share by at most 0.99 points (Bike customers, top 20%: 39.51 against 38.52; 113 customers tie at the boundary, group of 1,781 against 1,717). The FLOOR share is below the CEILING share by at most 0.05 points (No bikes customers, top 1%: 8.53 against 8.58). For all customers in 2013 the tie-inclusive shares are 6.15, 24.07, 38.10 and 63.46 against 6.09, 24.05, 37.53 and 62.89 under CEILING (3, 2, 113 and 80 customers tied at the boundary).

7. **Products (sections E1 and E2).** N is the number of products with revenue in the year.

   | Year | Active products (N) | Top 1 | Top 5 | Top 10 | Top 20 | Median revenue per product | Mean / median |
   |---|---|---|---|---|---|---|---|
   | 2011 | 37 | 16.9% | 78.1% | 90.9% | 98.5% | 14,679.00 | 13.03 |
   | 2012 | 80 | 7.3% | 33.6% | 64.2% | 92.2% | 1,660.50 | 43.98 |
   | 2013 | 102 | 5.9% | 29.1% | 44.6% | 67.0% | 39,133.00 | 4.10 |

   Under an equal distribution the top 10 products would hold 10 / 37 = 27.0%, 10 / 80 = 12.5% and 10 / 102 = 9.8% of revenue. No product ties at the boundary of any cut (section E2, 1 product at each); the 2013 tie at ranks 3 and 4 falls inside the cuts, not at their boundary.

8. **The largest products and the categories (sections E3 and F).** The 10 largest products of each year are all in the category Bikes. In 2011 the five largest have 14.2% to 16.9% of revenue each and the sixth 2.9%. In 2013 the six largest have 5.5% to 5.9% each and the seventh 2.6% (417,200 against 902,480 for the sixth); ranks 3 and 4 tie at 947,835. In 2012, 30 of the 80 active products are Accessories (19) or Clothing (11) with revenue 2,146 + 642 = 2,788 (2,788 / 5,842,231 = 0.05% of the year's revenue); the other 50 are Bikes (5,839,443). In 2013 Bikes are 60 of 102 active products (58.8%) and 93.9% of revenue; Accessories (22 products) are 4.1% and Clothing (20 products) 2.0% (the shares tie to Q2 section C).

### Inferences

1. **The customer concentration of 2011 and 2012 is context only, even where the "interpretable" flag says "yes", and customer shares are not compared across years.** In 2011 every customer has one order and revenue per customer is the price of one bike (observations 1 and 2; Q1 section A has 2,216 orders, lines and units, and Q3 section A 2,216 customers in the 2011 cohort). Many customers have exactly the same revenue (1,544 in 2011; 431 to 749 tied at the cut boundaries in 2012), so the share of a top group is mostly a matter of how many customers are tied: the 5% cut (k = 111) gives 5.61% under CEILING and 78.08% under the tie-inclusive rule (section D). In 2012, 3,241 of 3,255 customers have one order and 431 to 749 customers tie at the boundary of the cuts (1.67% against 19.23% at the 1% cut). The flag checks only N and k. The figures say how prices are spread, not how customers differ.
2. **The customer result of Q4 is 2013 within each group, and the all-customers figures of section B reflect the group mix.** The 2013 top 20% of all customers holds 62.9% (observation 3), more than the top 20% of either group (38.5% and 48.4%, observation 5). The two groups have similar numbers of active customers (49.3% and 50.7%) but 96.4% and 3.6% of revenue (observation 4). Every top group of all customers in 2013 contains only Bike customers (observation 4), so the shares of section B for 2013 rank Bike customers against the revenue and the customer count of both groups.
3. **Inside each 2013 group, the top groups hold the shares of observation 5 against the equal-distribution reference.** The top 20% holds 38.5% and 48.4% of the group's revenue (1.9 and 2.4 times the reference); the top 1% holds 3.6% and 8.6% (3.6 and 8.6 times). The No bikes group holds a larger share than the Bike group at every cut, and the difference between rules is below one point (observation 6), so the reading does not change with the rule. These shares describe how revenue is spread among customers within a year, which may reflect prices and the number of orders; the output does not separate them. They do not say why, and they are not a statement about any business risk.
4. **Customers with two or more orders in 2013 are a minority of customers, whose share of revenue (27.6%) is larger than their share of customers (15.3%).** They are 15.3% of active customers and 27.6% of revenue (observation 1). A customer's yearly revenue combines the number of orders and the value per order, and the output does not separate them within the groups, so the concentration of observation 5 is not attributed to either.
5. **Products: the 10 largest are Bikes in every year, and a revenue share combines price and volume; it is not a measure of popularity.** The top cuts of observation 7 are given with N and are not compared across years: N (37, 80, 102) and the catalog change (in 2012, 30 of 80 products are Accessories or Clothing with 2,788 of revenue, observation 8), so a cut of a given size is not the same kind of group in each year. Within a year the output shows that a small group of Bike products accounts for much of the revenue, for example 44.6% for the 10 largest of 102 in 2013 against 9.8% under an equal distribution.

### Hypotheses (not established)

* The higher share of the No bikes group at every cut (observation 5) may reflect how many orders a customer placed and how early in 2013 they started, more than differences in what they spend per order. Not tested here: A splits customers by number of orders only for all customers together.
* The single value 3,578 shared by 1,544 customers in 2011 and the 431 to 749 ties in 2012 may reflect a list with few price points, or how the data was generated, more than customer behaviour. Cannot be tested with this data.
* Within the Bike group, the 2013 spread of revenue per customer (observation 5) may mostly reflect the spread of bike prices and the number of orders, as in 2011 and 2012. Not tested here: the output does not show orders per customer or revenue per order inside each group.

### Uncertainty

* Apart from the 2013 top groups of all customers (observation 4), the output does not show **who** is in a top group, whether the same customers or products stay in it **across years**, or its **composition** (for customers: what they buy, how many orders they placed, when they started; for products, only the category of the 10 largest and the category shares of revenue). Customers are not followed across years.
* A customer's yearly revenue may vary with the months in which the customer was active: in 2013 there are 12,521 customers whose first order is in 2013 (Q3 section A) and there is no No bikes order in 2011 or 2012 (Q2 section H; Q4 section C1). The ranking of customers may partly reflect when they started in the year; the output does not show this.
* The share of a top percentage is tied to N, which changes by year (2,216, 3,255, 17,427 customers; 37, 80, 102 products). Cuts of the same name are different groups in different years.
* The customer group (decision 7.10) uses the whole data, so a customer's group in one year can rest on an order of another year. In this data no customer has both a Bike order and a No bikes order (section G), so the group matches the customer's own orders in every year.
* Rank ties among products are broken by `product_number`; the shares do not change with the tie-break, but the lists can (2013, ranks 3 and 4).
* A product is a distinct `product_number`, current version only (Q2): a relaunch under a new number counts as two products. Category is the current version's.
* Product codes that differ only in suffix (for example `BK-M68B-42` / `-46`, or `BK-R93R-44` / `-48`) may be variants of one model. Product shares change with that grain and would differ at model level; no model-level figure was computed.
* Revenue is `SUM(sales_amount)` and the currency is unknown. The pattern may reflect how the data was produced.

### Needs additional data

* Customer identity resolution, if one person can hold several customer records (a person with two records appears as two customers).
* Information on how the data was generated, to interpret the single price value of 2011 and the absence of No bikes customers in 2011 and 2012.
