-- Analytics step 1: semantic view over all three patterns (Cortex Analyst)
-- Requires patterns 1-3.
USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

CREATE OR REPLACE SEMANTIC VIEW RIV2026DL_SNOW.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_SV
	tables (
		ACTIVITY as (
			SELECT "sps_customer_item_key" AS SPS_CUSTOMER_ITEM_KEY, "sps_retailer_name_key" AS SPS_RETAILER_NAME_KEY, "sps_customer_location_key" AS SPS_CUSTOMER_LOCATION_KEY, "period_ending_date" AS PERIOD_ENDING_DATE, "gross_sales_units" AS GROSS_SALES_UNITS, "gross_sales_retail" AS GROSS_SALES_RETAIL, "net_sales_units" AS NET_SALES_UNITS, "net_sales_cost" AS NET_SALES_COST, "net_sales_retail" AS NET_SALES_RETAIL, "net_sales_margin_value" AS NET_SALES_MARGIN_VALUE, "customer_return_units" AS CUSTOMER_RETURN_UNITS, "customer_return_retail" AS CUSTOMER_RETURN_RETAIL, "inventory_units" AS INVENTORY_UNITS, "inventory_cost" AS INVENTORY_COST, "inventory_retail" AS INVENTORY_RETAIL, "on_order_units" AS ON_ORDER_UNITS, "receipt_units" AS RECEIPT_UNITS, "in_transit_units" AS IN_TRANSIT_UNITS, "return_to_vendor_units" AS RETURN_TO_VENDOR_UNITS, "inventory_adjustment_units" AS INVENTORY_ADJUSTMENT_UNITS, "permanent_markdown_values" AS PERMANENT_MARKDOWN_VALUES, "point_of_sale_markdown_values" AS POINT_OF_SALE_MARKDOWN_VALUES, "total_markdown_values" AS TOTAL_MARKDOWN_VALUES, "insert_timestamp" AS INSERT_TIMESTAMP, "batch_seq" AS BATCH_SEQ FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity"
		) with synonyms=('sales and inventory activity','POS data','sell-through data','retail activity') comment='Core fact table (Iceberg, S3 Tables catalog RIV_DEMO_S3T_DB.rivdemo_ingest.activity). One row per retailer x item x store/DC x weekly period ending date, as reported by retail trading partners to a brand/supplier that distributes product through multiple retailers. Contains point-of-sale sales, customer returns, on-hand inventory, on-order, receipts, in-transit, return-to-vendor, inventory adjustments and markdowns. Inventory/on-order/in-transit values are point-in-time snapshots and should not be summed across periods.',
		PRODUCTS as (
			SELECT "sps_retailer_name_key" AS SPS_RETAILER_NAME_KEY, "sps_customer_item_key" AS SPS_CUSTOMER_ITEM_KEY, "vendor_name" AS VENDOR_NAME, "brand_name" AS BRAND_NAME, "division_name" AS DIVISION_NAME, "department_name" AS DEPARTMENT_NAME, "class_name" AS CLASS_NAME, "category_name" AS CATEGORY_NAME, "sub_category_name" AS SUB_CATEGORY_NAME, "gender" AS GENDER, "style_description" AS STYLE_DESCRIPTION, "color_name" AS COLOR_NAME, "size_name" AS SIZE_NAME, "upc" AS UPC, "sku" AS SKU, "product_description" AS PRODUCT_DESCRIPTION, "product_season" AS PRODUCT_SEASON, "replenishment_indicator" AS REPLENISHMENT_INDICATOR, "markdown_indicator" AS MARKDOWN_INDICATOR, "cost" AS COST, "msrp" AS MSRP FROM RIV2026DATALAKEDEMO."rivdemo_2026"."item"
		) primary key (SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_ITEM_KEY) with synonyms=('items','item master','SKUs','merchandise') comment='Item / product master (Iceberg, catalog-linked RIV2026DATALAKEDEMO.rivdemo_2026.item). One row per retailer item: vendor, brand, merchandise hierarchy (division > department > class > category), style, color, size, UPC/SKU, unit cost, MSRP and season.',
		STORES as (
			SELECT "sps_retailer_name_key" AS SPS_RETAILER_NAME_KEY, "sps_customer_location_key" AS SPS_CUSTOMER_LOCATION_KEY, "store_number" AS STORE_NUMBER, "store_name" AS STORE_NAME, "city" AS CITY, "state" AS STATE, "country" AS COUNTRY, "region" AS REGION, "sps_location_type" AS SPS_LOCATION_TYPE, "climate" AS CLIMATE, "demographic" AS DEMOGRAPHIC, "banner" AS BANNER, "store_size" AS STORE_SIZE, "comp_store_indicator" AS COMP_STORE_INDICATOR FROM RIV2026DATALAKEDEMO."rivdemo_2026"."location"
		) primary key (SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_LOCATION_KEY) with synonyms=('locations','doors','points of distribution','store master') comment='Location master (Iceberg, catalog-linked RIV2026DATALAKEDEMO.rivdemo_2026.location). One row per retailer selling location: physical stores and INTERNET (e-commerce). Includes geography, region, climate, demographic, banner, store size and comparable-store indicator.',
		RETAILERS as (
			SELECT "sps_retailer_name_key" AS SPS_RETAILER_NAME_KEY, "activitygrain" AS ACTIVITY_GRAIN FROM RIV2026DATALAKEDEMO."rivdemo_2026"."retailer_metadata"
		) primary key (SPS_RETAILER_NAME_KEY) with synonyms=('retail partners','trading partners','accounts','customers') comment='Retailer (trading partner) reference (RIV2026DATALAKEDEMO.rivdemo_2026.retailer_metadata): the 12 retail accounts the brand distributes through and their reporting grain (WEEKLY).',
		ACTIVITY_SUMMARY as RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT with synonyms=('activity rollup','aggregated sales','summary table','near real-time summary') comment='Dynamic Iceberg Table refreshed incrementally with 1-minute target lag. Pre-joins activity with item, location and retailer and aggregates by load minute, period, retailer, region, state, brand, department and category. Best for data freshness / load latency questions and quick summaries at those grains.'
	)
	relationships (
		ACTIVITY_TO_PRODUCTS as ACTIVITY(SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_ITEM_KEY) references PRODUCTS(SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_ITEM_KEY),
		ACTIVITY_TO_RETAILERS as ACTIVITY(SPS_RETAILER_NAME_KEY) references RETAILERS(SPS_RETAILER_NAME_KEY),
		ACTIVITY_TO_STORES as ACTIVITY(SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_LOCATION_KEY) references STORES(SPS_RETAILER_NAME_KEY,SPS_CUSTOMER_LOCATION_KEY),
		PRODUCTS_TO_RETAILERS as PRODUCTS(SPS_RETAILER_NAME_KEY) references RETAILERS(SPS_RETAILER_NAME_KEY),
		STORES_TO_RETAILERS as STORES(SPS_RETAILER_NAME_KEY) references RETAILERS(SPS_RETAILER_NAME_KEY),
		SUMMARY_TO_RETAILERS as ACTIVITY_SUMMARY(RETAILER_KEY) references RETAILERS(SPS_RETAILER_NAME_KEY)
	)
	facts (
		ACTIVITY.GROSS_SALES_UNITS as GROSS_SALES_UNITS comment='Units sold before customer returns',
		ACTIVITY.GROSS_SALES_RETAIL as GROSS_SALES_RETAIL comment='Sales dollars at retail before returns',
		ACTIVITY.NET_SALES_UNITS as NET_SALES_UNITS with synonyms=('units sold','sell-through units') comment='Units sold net of customer returns',
		ACTIVITY.NET_SALES_RETAIL as NET_SALES_RETAIL with synonyms=('revenue','sales dollars','net sales') comment='Net sales dollars at retail price (after returns)',
		ACTIVITY.NET_SALES_COST as NET_SALES_COST with synonyms=('COGS','cost of goods sold') comment='Cost of net units sold',
		ACTIVITY.NET_SALES_MARGIN as NET_SALES_MARGIN_VALUE with synonyms=('gross margin dollars','profit') comment='Net sales retail minus net sales cost',
		ACTIVITY.RETURN_UNITS as CUSTOMER_RETURN_UNITS comment='Units returned by shoppers to the retailer',
		ACTIVITY.RETURN_RETAIL as CUSTOMER_RETURN_RETAIL comment='Retail dollars of customer returns',
		ACTIVITY.ON_HAND_UNITS as INVENTORY_UNITS with synonyms=('inventory','stock','on hand') comment='End-of-period on-hand inventory units at the location (snapshot)',
		ACTIVITY.ON_HAND_COST as INVENTORY_COST comment='End-of-period on-hand inventory at cost (snapshot)',
		ACTIVITY.ON_HAND_RETAIL as INVENTORY_RETAIL comment='End-of-period on-hand inventory at retail (snapshot)',
		ACTIVITY.ON_ORDER_UNITS as ON_ORDER_UNITS with synonyms=('open orders','PO units') comment='Units on open purchase orders not yet received (snapshot)',
		ACTIVITY.RECEIPT_UNITS as RECEIPT_UNITS with synonyms=('DC receipts','received units','shipments received') comment='Units received into the location during the period',
		ACTIVITY.IN_TRANSIT_UNITS as IN_TRANSIT_UNITS with synonyms=('shipped not received','pipeline units') comment='Units shipped by the distributor/DC but not yet received by the location (snapshot)',
		ACTIVITY.RTV_UNITS as RETURN_TO_VENDOR_UNITS with synonyms=('RTV','vendor returns') comment='Units sent back from the retailer to the supplier',
		ACTIVITY.ADJUSTMENT_UNITS as INVENTORY_ADJUSTMENT_UNITS with synonyms=('shrink','shrinkage','inventory adjustments') comment='Inventory adjustment units (shrink, damage, count corrections). Negative = loss.',
		ACTIVITY.MARKDOWN_VALUE as TOTAL_MARKDOWN_VALUES with synonyms=('markdowns','discounts') comment='Total markdown dollars (permanent + point-of-sale)',
		ACTIVITY.PERMANENT_MARKDOWN_VALUE as PERMANENT_MARKDOWN_VALUES comment='Permanent price reduction markdown dollars',
		ACTIVITY.POS_MARKDOWN_VALUE as POINT_OF_SALE_MARKDOWN_VALUES comment='Promotional point-of-sale markdown dollars',
		PRODUCTS.UNIT_COST as COST comment='Supplier unit cost of the item',
		PRODUCTS.MSRP as MSRP with synonyms=('list price','suggested retail price') comment='Manufacturer suggested retail price',
		ACTIVITY_SUMMARY.SUM_NET_SALES_RETAIL as NET_SALES_RETAIL comment='Pre-aggregated net sales dollars',
		ACTIVITY_SUMMARY.SUM_NET_SALES_UNITS as NET_SALES_UNITS comment='Pre-aggregated net sales units',
		ACTIVITY_SUMMARY.SUM_NET_MARGIN as NET_MARGIN comment='Pre-aggregated net margin dollars',
		ACTIVITY_SUMMARY.SUM_ON_HAND_UNITS as ON_HAND_UNITS comment='Pre-aggregated on-hand units (snapshot)',
		ACTIVITY_SUMMARY.SOURCE_ROW_COUNT as ROW_COUNT comment='Number of detail activity rows rolled up into this summary row'
	)
	dimensions (
		ACTIVITY.PERIOD_ENDING_DATE as PERIOD_ENDING_DATE with synonyms=('week ending','fiscal week','period','date') comment='Week-ending date of the reporting period',
		ACTIVITY.LOAD_TIMESTAMP as INSERT_TIMESTAMP comment='When the row was loaded into the data lake',
		ACTIVITY.BATCH_SEQ as BATCH_SEQ comment='Ingestion batch sequence number',
		PRODUCTS.BRAND_NAME as BRAND_NAME with synonyms=('brand','label') comment='Brand of the product',
		PRODUCTS.VENDOR_NAME as VENDOR_NAME with synonyms=('supplier','manufacturer') comment='Vendor / supplier that distributes the item to the retailer',
		PRODUCTS.DIVISION_NAME as DIVISION_NAME comment='Top level of the merchandise hierarchy',
		PRODUCTS.DEPARTMENT_NAME as DEPARTMENT_NAME with synonyms=('department','dept') comment='Merchandise department: Womens Apparel, Mens/Unisex Apparel, Womens Footwear, Mens/Unisex Footwear, Kids Footwear',
		PRODUCTS.CLASS_NAME as CLASS_NAME comment='Merchandise class',
		PRODUCTS.CATEGORY_NAME as CATEGORY_NAME with synonyms=('category','product category') comment='Product category: APPAREL or FOOTWEAR',
		PRODUCTS.SUB_CATEGORY_NAME as SUB_CATEGORY_NAME comment='Product sub-category',
		PRODUCTS.GENDER as GENDER comment='Target gender of the product',
		PRODUCTS.STYLE_DESCRIPTION as STYLE_DESCRIPTION with synonyms=('style','product name') comment='Style description',
		PRODUCTS.COLOR_NAME as COLOR_NAME with synonyms=('color') comment='Item color',
		PRODUCTS.SIZE_NAME as SIZE_NAME with synonyms=('size') comment='Item size',
		PRODUCTS.UPC as UPC with synonyms=('barcode','GTIN') comment='Universal product code',
		PRODUCTS.SKU as SKU comment='Retailer SKU',
		PRODUCTS.PRODUCT_DESCRIPTION as PRODUCT_DESCRIPTION comment='Product description',
		PRODUCTS.PRODUCT_SEASON as PRODUCT_SEASON with synonyms=('season') comment='Season the product belongs to',
		PRODUCTS.REPLENISHMENT_INDICATOR as REPLENISHMENT_INDICATOR with synonyms=('basic','never out of stock','NOS') comment='Whether the item is on automatic replenishment from the distributor',
		PRODUCTS.MARKDOWN_INDICATOR as MARKDOWN_INDICATOR comment='Whether the item is currently marked down',
		STORES.STORE_NAME as STORE_NAME with synonyms=('store','door','location') comment='Store / location name',
		STORES.STORE_NUMBER as STORE_NUMBER comment='Retailer store number',
		STORES.CITY as CITY comment='Store city',
		STORES.STATE as STATE with synonyms=('province') comment='Store state / province',
		STORES.COUNTRY as COUNTRY comment='Store country',
		STORES.REGION as REGION with synonyms=('territory','market') comment='Sales region: Europe, Northeast, South, Midwest, Unknown',
		STORES.LOCATION_TYPE as SPS_LOCATION_TYPE with synonyms=('channel','store type') comment='STORE (physical) or INTERNET (e-commerce)',
		STORES.CLIMATE as CLIMATE comment='Climate zone of the store',
		STORES.DEMOGRAPHIC as DEMOGRAPHIC comment='Shopper demographic profile of the store',
		STORES.BANNER as BANNER comment='Retail banner / store brand',
		STORES.STORE_SIZE as STORE_SIZE comment='Store size classification',
		STORES.COMP_STORE_INDICATOR as COMP_STORE_INDICATOR with synonyms=('comp store','comparable store','like for like') comment='Whether the store is a comparable store',
		RETAILERS.RETAILER_NAME as SPS_RETAILER_NAME_KEY with synonyms=('retailer','account','trading partner','customer') comment='Retail trading partner: Big Box, Department Store, Discount, Mall, Outdoor, Specialty, Sports, Luxury, Shoe, European, British and Swiss Retailer',
		RETAILERS.ACTIVITY_GRAIN as ACTIVITY_GRAIN comment='Reporting grain of the retailer (WEEKLY)',
		ACTIVITY_SUMMARY.SUMMARY_LOAD_MINUTE as LOAD_MINUTE comment='Minute the underlying rows were loaded to the lake',
		ACTIVITY_SUMMARY.SUMMARY_PERIOD_ENDING_DATE as PERIOD_ENDING_DATE comment='Week-ending date (summary)',
		ACTIVITY_SUMMARY.SUMMARY_REGION as REGION comment='Region (summary)',
		ACTIVITY_SUMMARY.SUMMARY_STATE as STATE comment='State (summary)',
		ACTIVITY_SUMMARY.SUMMARY_BRAND as BRAND_NAME comment='Brand (summary)',
		ACTIVITY_SUMMARY.SUMMARY_DEPARTMENT as DEPARTMENT_NAME comment='Department (summary)',
		ACTIVITY_SUMMARY.SUMMARY_CATEGORY as CATEGORY_NAME comment='Category (summary)',
		ACTIVITY_SUMMARY.LAST_LOADED_AT as LAST_LOADED_AT comment='Latest load timestamp of rows in this summary row'
	)
	metrics (
		ACTIVITY.TOTAL_NET_SALES as SUM(activity.net_sales_retail) with synonyms=('revenue','sales','net sales $') comment='Total net sales dollars at retail',
		ACTIVITY.TOTAL_NET_UNITS as SUM(activity.net_sales_units) with synonyms=('units sold') comment='Total net units sold',
		ACTIVITY.TOTAL_GROSS_SALES as SUM(activity.gross_sales_retail) comment='Total gross sales dollars',
		ACTIVITY.TOTAL_MARGIN as SUM(activity.net_sales_margin) with synonyms=('gross margin $','profit') comment='Total net margin dollars',
		ACTIVITY.MARGIN_PCT as DIV0(SUM(activity.net_sales_margin), SUM(activity.net_sales_retail)) with synonyms=('gross margin %','GM%') comment='Net margin as a fraction of net sales',
		ACTIVITY.RETURN_RATE as DIV0(SUM(activity.return_units), SUM(activity.gross_sales_units)) with synonyms=('return %') comment='Customer return units divided by gross units sold',
		ACTIVITY.TOTAL_MARKDOWNS as SUM(activity.markdown_value) comment='Total markdown dollars',
		ACTIVITY.MARKDOWN_PCT as DIV0(SUM(activity.markdown_value), SUM(activity.gross_sales_retail)) with synonyms=('markdown rate') comment='Markdown dollars as a fraction of gross sales',
		ACTIVITY.TOTAL_ON_HAND_UNITS as SUM(activity.on_hand_units) with synonyms=('inventory units','stock on hand') comment='On-hand units. Snapshot: filter to a single period (usually the latest) before summing',
		ACTIVITY.TOTAL_ON_HAND_COST as SUM(activity.on_hand_cost) comment='On-hand inventory value at cost (snapshot)',
		ACTIVITY.TOTAL_ON_ORDER_UNITS as SUM(activity.on_order_units) comment='Units on order (snapshot)',
		ACTIVITY.TOTAL_IN_TRANSIT_UNITS as SUM(activity.in_transit_units) with synonyms=('distribution pipeline') comment='Units in transit from distributor to location (snapshot)',
		ACTIVITY.TOTAL_RECEIPTS as SUM(activity.receipt_units) comment='Units received',
		ACTIVITY.TOTAL_RTV_UNITS as SUM(activity.rtv_units) comment='Units returned to vendor',
		ACTIVITY.TOTAL_SHRINK_UNITS as SUM(activity.adjustment_units) with synonyms=('shrink') comment='Net inventory adjustment units (negative = loss)',
		ACTIVITY.SELL_THROUGH_PCT as DIV0(SUM(activity.net_sales_units), SUM(activity.net_sales_units) + SUM(activity.on_hand_units)) with synonyms=('sell through','sell-thru') comment='Net units sold / (net units sold + on-hand units)',
		ACTIVITY.WEEKS_OF_SUPPLY as DIV0(SUM(activity.on_hand_units), SUM(activity.net_sales_units)) with synonyms=('WOS','weeks of cover') comment='On-hand units divided by weekly net units sold; use for a single week',
		ACTIVITY.AVG_UNIT_RETAIL as DIV0(SUM(activity.net_sales_retail), SUM(activity.net_sales_units)) with synonyms=('AUR','average selling price') comment='Average unit retail',
		ACTIVITY.AVG_UNIT_COST as DIV0(SUM(activity.net_sales_cost), SUM(activity.net_sales_units)) with synonyms=('AUC') comment='Average unit cost',
		ACTIVITY.ACTIVITY_ROW_COUNT as COUNT(*) comment='Number of activity rows',
		PRODUCTS.ITEM_COUNT as COUNT(DISTINCT products.SPS_CUSTOMER_ITEM_KEY) with synonyms=('number of SKUs','assortment size') comment='Distinct items',
		STORES.STORE_COUNT as COUNT(DISTINCT stores.SPS_CUSTOMER_LOCATION_KEY) with synonyms=('door count') comment='Distinct locations',
		ACTIVITY_SUMMARY.SUMMARY_NET_SALES as SUM(activity_summary.sum_net_sales_retail) comment='Net sales from the near real-time summary',
		ACTIVITY_SUMMARY.SUMMARY_NET_UNITS as SUM(activity_summary.sum_net_sales_units) comment='Net units from the near real-time summary',
		ACTIVITY_SUMMARY.SUMMARY_ROWS_LOADED as SUM(activity_summary.source_row_count) comment='Detail rows loaded, from the summary',
		ACTIVITY_SUMMARY.LATEST_LOAD_TIME as MAX(activity_summary.last_loaded_at) with synonyms=('data freshness','last refresh') comment='Most recent load timestamp in the data'
	)
	comment='Retail sell-through, inventory and distribution analytics for a consumer brand / supplier that distributes apparel and footwear through 12 retail trading partners (big box, department store, specialty, sports, luxury, European, etc.). Combines Iceberg tables from the S3 Tables lake (activity), the data-lake catalog (item, location, retailer) and a Snowflake Dynamic Iceberg Table rollup.'
	ai_sql_generation 'This is a retailer / distribution sell-through model. Inventory measures (on hand, on order, in transit) are snapshots: unless the user asks for a trend, filter to the latest period_ending_date before summing. Sales, returns, receipts and markdowns are additive across periods. Express percentages as fractions rounded to 4 decimals. Use activity_summary only for data freshness, load latency or quick summaries by region/state/brand/department/category; otherwise use activity joined with products, stores and retailers. Latest week means MAX(period_ending_date).'
	ai_verified_queries (
		VQ_SALES_MARGIN_BY_BRAND_LATEST AS ( 
QUESTION 'What are net sales and margin percent by brand for the latest week?' 
ONBOARDING_QUESTION true
SQL 'SELECT p.brand_name, SUM(a.net_sales_retail) AS net_sales, DIV0(SUM(a.net_sales_margin), SUM(a.net_sales_retail)) AS margin_pct FROM __activity a JOIN __products p ON a.sps_retailer_name_key = p.sps_retailer_name_key AND a.sps_customer_item_key = p.sps_customer_item_key WHERE a.period_ending_date = (SELECT MAX(period_ending_date) FROM __activity) GROUP BY 1 ORDER BY net_sales DESC'),
		VQ_SALES_BY_REGION_DEPARTMENT AS ( 
QUESTION 'What are net sales by region and department?' 
ONBOARDING_QUESTION true
SQL 'SELECT s.region, p.department_name, SUM(a.net_sales_retail) AS net_sales FROM __activity a JOIN __products p ON a.sps_retailer_name_key = p.sps_retailer_name_key AND a.sps_customer_item_key = p.sps_customer_item_key JOIN __stores s ON a.sps_retailer_name_key = s.sps_retailer_name_key AND a.sps_customer_location_key = s.sps_customer_location_key GROUP BY 1, 2 ORDER BY 1, net_sales DESC'),
		VQ_RETURN_RATE_BY_DEPARTMENT AS ( 
QUESTION 'What is the customer return rate by department?' 
SQL 'SELECT p.department_name, DIV0(SUM(a.return_units), SUM(a.gross_sales_units)) AS return_rate FROM __activity a JOIN __products p ON a.sps_retailer_name_key = p.sps_retailer_name_key AND a.sps_customer_item_key = p.sps_customer_item_key GROUP BY 1 ORDER BY return_rate DESC'),
		VQ_SELL_THROUGH_WOS_BY_CATEGORY AS ( 
QUESTION 'Which categories are overstocked based on sell-through and weeks of supply for the latest week?' 
ONBOARDING_QUESTION true
SQL 'SELECT p.category_name, SUM(a.net_sales_units) AS net_units, SUM(a.on_hand_units) AS on_hand_units, DIV0(SUM(a.net_sales_units), SUM(a.net_sales_units) + SUM(a.on_hand_units)) AS sell_through_pct, DIV0(SUM(a.on_hand_units), SUM(a.net_sales_units)) AS weeks_of_supply FROM __activity a JOIN __products p ON a.sps_retailer_name_key = p.sps_retailer_name_key AND a.sps_customer_item_key = p.sps_customer_item_key WHERE a.period_ending_date = (SELECT MAX(period_ending_date) FROM __activity) GROUP BY 1 ORDER BY weeks_of_supply DESC'),
		VQ_DISTRIBUTION_PIPELINE_BY_RETAILER AS ( 
QUESTION 'How many units are in transit and on order by retailer for the latest week?' 
SQL 'SELECT r.retailer_name, SUM(a.in_transit_units) AS in_transit_units, SUM(a.on_order_units) AS on_order_units, SUM(a.on_hand_units) AS on_hand_units FROM __activity a JOIN __retailers r ON a.sps_retailer_name_key = r.sps_retailer_name_key WHERE a.period_ending_date = (SELECT MAX(period_ending_date) FROM __activity) GROUP BY 1 ORDER BY in_transit_units DESC'),
		VQ_MARKDOWN_PCT_BY_BRAND_SEASON AS ( 
QUESTION 'What is the markdown percent by brand and season?' 
SQL 'SELECT p.brand_name, p.product_season, SUM(a.markdown_value) AS markdowns, DIV0(SUM(a.markdown_value), SUM(a.gross_sales_retail)) AS markdown_pct FROM __activity a JOIN __products p ON a.sps_retailer_name_key = p.sps_retailer_name_key AND a.sps_customer_item_key = p.sps_customer_item_key GROUP BY 1, 2 ORDER BY markdown_pct DESC'),
		VQ_CHANNEL_SALES AS ( 
QUESTION 'How do store and internet channel sales compare by retailer?' 
SQL 'SELECT r.retailer_name, s.location_type, SUM(a.net_sales_retail) AS net_sales, SUM(a.net_sales_units) AS net_units FROM __activity a JOIN __stores s ON a.sps_retailer_name_key = s.sps_retailer_name_key AND a.sps_customer_location_key = s.sps_customer_location_key JOIN __retailers r ON a.sps_retailer_name_key = r.sps_retailer_name_key GROUP BY 1, 2 ORDER BY 1, 2'),
		VQ_SHRINK_BY_STORE AS ( 
QUESTION 'Which stores have the most inventory shrink?' 
SQL 'SELECT s.store_name, SUM(a.adjustment_units) AS shrink_units FROM __activity a JOIN __stores s ON a.sps_retailer_name_key = s.sps_retailer_name_key AND a.sps_customer_location_key = s.sps_customer_location_key GROUP BY 1 ORDER BY shrink_units ASC LIMIT 10'),
		VQ_WEEKLY_SALES_TREND AS ( 
QUESTION 'What is the weekly net sales trend?' 
SQL 'SELECT a.period_ending_date, SUM(a.net_sales_retail) AS net_sales, SUM(a.net_sales_units) AS net_units FROM __activity a GROUP BY 1 ORDER BY 1'),
		VQ_DATA_FRESHNESS AS ( 
QUESTION 'How fresh is the data and how many rows were loaded per minute?' 
ONBOARDING_QUESTION true
SQL 'SELECT summary_load_minute, SUM(source_row_count) AS rows_loaded, MAX(last_loaded_at) AS last_loaded_at FROM __activity_summary GROUP BY 1 ORDER BY 1 DESC LIMIT 20')
	);
