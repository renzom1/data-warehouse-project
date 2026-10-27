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
* The 11,581 orders without a Bike in 2013 (section H) may be later purchases by customers who already bought a Bike, rather than purchases by a different kind of customer. This analysis works at order level and cannot distinguish the two.
* Discounting or a list-price change may sit behind realized prices. Cannot be separated here.

### Uncertainty

* How much of the AOV decline each factor accounts for. No price–mix or AOV decomposition was done, so mix, price and order structure are described, not apportioned. The additive category split of section D apportions the changes by category, not by factor, and the counterfactual in Inferences (fourth item) separates the shift across Bike subcategories from the change within them, 2012 to 2013.
* Product attributes are the current product version; a product's category could differ historically.
* Section I covers only products sold in two consecutive years, uses realized prices, and says nothing about entering or exiting products.
* 2011 and 2012 have few lines (2,216 and 3,397) against 52,798 in 2013; their shares and medians are less stable. 2013 itself changes within the year (Bike share of lines 29.9% in January 2013, 13.1% in February and 14.9% in March, section A2).
* Customer mix is not examined: whether orders without a Bike come from customers who already bought a Bike or from other customers is unknown. Country mix is not examined either. Both could contribute.
* The 2011 to 2012 reading uses annual averages and an annual price index. The monthly step from December 2011 to January 2012 (3,015.29 to 1,965.73, section A2; −34.8%, 1,965.73 / 3,015.29 = 0.652) was not decomposed at monthly grain, so which products drive it is unknown.
* "Product" means a distinct `product_number`. A relaunch under a new number would count as one product leaving and another entering, so new and exited products (sections G1, I) may overstate real assortment changes.

### Needs additional data

* List prices, discounts and price history, to separate price changes from discounting.
* Information on how the data was generated or extracted, to interpret the abrupt appearance of products and categories in December 2012 and the step in December 2011 to January 2012.
* A product-level price–mix decomposition (not done here) if the question of price against composition within Bikes must be answered.
