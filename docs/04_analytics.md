# 4. Semantic view and Cortex Agent

One semantic view spans all three patterns:

| Logical table | Source | Pattern |
|---|---|---|
| `ACTIVITY` | `RIV_DEMO_S3T_DB."rivdemo_ingest"."activity"` | 1 |
| `PRODUCTS`, `STORES`, `RETAILERS` | `RIV2026DATALAKEDEMO."rivdemo_2026".item / location / retailer_metadata` | 2 |
| `ACTIVITY_SUMMARY` | `RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT` | 3 |

The agent "Retail Distribution Analyst" uses it through Cortex Analyst, plus a charting tool.

Requires patterns 1 to 3.

## Steps in Snowsight (role RIV_DEMO_RL)
1. Run `sql/04_analytics/01_semantic_view.sql`. It creates
   `RIV2026DL_SNOW.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_SV`.
2. Run `sql/04_analytics/02_agent.sql`. It creates
   `RIV2026DL_SNOW.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_AGENT`.
3. Open **AI & ML -> Agents -> Retail Distribution Analyst** (or Snowflake Intelligence)
   and try the sample questions:
   - What are net sales and margin % by department?
   - Which categories are overstocked based on weeks of supply?
   - Which retailers have the most units in transit right now?
   - Which 5 stores have the worst shrink?
   - Show the weekly net sales trend
   - How fresh is the data?

## Demo flow
1. Start the Lambda (docs/01_s3tables.md).
2. Ask "How fresh is the data?" and note the last load time.
3. Wait one to two minutes and ask again: the answer moves forward, because the DT has
   picked up the new batches.

## Notes
- Brand is mostly `UNKNOWN` in this data; use department or category.
- Each retailer reports one channel, so channel comparisons equal retailer comparisons.
- To use Snowflake Intelligence, the agent may need to be added to your account's
  Snowflake Intelligence object; see the Snowflake docs for your account setup.
