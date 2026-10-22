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

* Changes in the product mix (what is sold, and in which combinations) may explain part of the decline in AOV and of the change in order structure. This has not been tested. Q2 will investigate it by comparing category and product-line shares by year, revenue per line, and each category's contribution to the year-over-year changes in lines and revenue. Even if product-mix changes are found, they will not necessarily explain the full decline in AOV.
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

Source: [`02_product_mix.sql`](02_product_mix.sql), output in [`output/02_product_mix.txt`](output/02_product_mix.txt). Sections are cited by letter. Every section reconciles to the control totals (section J, all `OK`: 60,398 lines, 27,659 orders, revenue 29,356,250, units 60,423). Order classes are defined in [decision 7.8](../docs/decisions.md#78-order-classes-by-product-category). No price–mix decomposition was done; section I is a simple like-for-like comparison.

AOV = lines per order × revenue per line (section A1):

| Year | Lines | Orders | Lines per order | Revenue per line | AOV | Bike lines, % of lines |
|---|---|---|---|---|---|---|
| 2011 | 2,216 | 2,216 | 1.00 | 3,192.73 | 3,192.73 | 100.0 |
| 2012 | 3,397 | 3,269 | 1.04 | 1,719.82 | 1,787.16 | 96.2 |
| 2013 | 52,798 | 21,287 | 2.48 | 309.67 | 768.07 | 18.4 |

Revenue per line fell by 46.1% (1,719.82 / 3,192.73 = 0.539) and by 82.0% (309.67 / 1,719.82 = 0.180).

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
3. **Accessories and Clothing first appear in December 2012, the month lines first exceed orders (sections A2, G2, G3, G4).**
   * First month with sales: Bikes December 2010 (context tail), Accessories and Clothing December 2012 (106 and 22 lines; 19 and 11 products).
   * Non-Bike share of lines: 26.5% in December 2012, 70.1% in January 2013, 86.9% in February 2013. AOV in the same months: 1,759.03, 1,357.21, 542.73.
   * Average unit price of Bikes in January to April 2013: 1,669.70, 1,550.08, 1,591.60, 1,604.02 (November 2012, when every line was a Bike: AOV 1,660.24).
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
8. **Assortment (section G1).** Bike products sold: 37 (2011), 50 (2012), 60 (2013). Of the 50 in 2012, 26 are new (29.3% of that year's Bike revenue) and 24 were also sold in 2011, so 37 − 24 = 13 products of 2011 were not sold in 2012. In 2013, 25 of 60 Bike products are new (18.5% of Bike revenue).

### Inferences

* **2012 to 2013: product mix is a large part of the change.** Accessories and Clothing, with revenue per line of 19.41 and 37.27, are 81.6% of 2013 lines (100 − 18.4), and 54.4% of 2013 orders contain no Bike (AOV 50.64). They appear in the same month in which lines first exceed orders and the second AOV step starts. The rise in lines per order and the fall in revenue per line coincide with the arrival of low-priced items. This describes the composition of the data; it does not show why they entered.
* **The mix does not explain all of the decline.** Orders that contain a Bike have an AOV of 1,624.09 in 2013, 9.1% below the 2012 AOV of 1,787.16 (1,624.09 / 1,787.16 = 0.909). The classes are not identical to 2012's (Bikes + other include accessory lines), so this only indicates that a decline remains.
* **2011 to 2012: not a category-mix effect.** Lines are 96.2% to 100% Bikes, and the AOV of Bikes-only orders fell to 1,787.33. It is also not a price cut on products sold in both years: none of the 24 was sold at a lower price, and their price index is +1.3%. What changed is which Bike products are sold: 13 of the 37 products of 2011 were not sold in 2012, 26 of the 50 sold in 2012 are new, and 18 Bike products were first sold in December 2011 and January 2012, around the step. This is consistent with a change in the mix of Bike products (the average Bike unit price fell 44.1% while continuing products did not get cheaper), but the data does not test it directly.
* **2012 to 2013 within Bikes.** The like-for-like price index is +7.7% while the average Bike unit price fell 11.4%, so the fall is not a lower price of the same products. It comes from within the subcategories: revenue per line fell 22.7% in Road Bikes (1,647.31 to 1,273.37; 1,273.37 / 1,647.31 = 0.773) and 11.4% in Mountain Bikes (2,061.15 to 1,825.97; 0.886) (section E2). Touring Bikes (1,774.93 in 2013) are above the 2013 Bike average of 1,582.35 and so raise it. Which Road and Mountain products drive the fall was not analyzed.

### Hypotheses (not established)

* In 2012, lower-priced Bike models replaced higher-priced ones. Not tested: this analysis does not compare the price level of the 13 products that left with the 26 that entered.
* The simultaneous appearance of 49 products and two new categories in December 2012 reflects how the dataset was produced (or a business launch), not a gradual change. Cannot be tested with this data.
* Discounting or a list-price change may sit behind realized prices. Cannot be separated here.

### Uncertainty

* How much of the AOV decline each factor accounts for. No decomposition was done, so mix, price and order structure are described, not apportioned.
* Product attributes are the current product version; a product's category could differ historically.
* Section I covers only products sold in two consecutive years, uses realized prices, and says nothing about entering or exiting products.
* 2011 and 2012 have few lines (2,216 and 3,397) against 52,798 in 2013; their shares and medians are less stable. 2013 itself changes within the year (Bike share of lines 29.9% in January 2013 and 14.9% in March, section A2).
* Customer or country mix is not examined and could contribute.

### Needs additional data

* List prices, discounts and price history, to separate price changes from discounting.
* Information on how the data was generated or extracted, to interpret the abrupt appearance of products and categories in December 2012 and the step in December 2011 to January 2012.
* A product-level price–mix decomposition (not done here) if the question of price against composition within Bikes must be answered.
