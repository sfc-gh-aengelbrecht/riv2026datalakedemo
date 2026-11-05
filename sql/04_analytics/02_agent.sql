-- Analytics step 2: Cortex Agent on the semantic view
-- Open it in Snowsight: AI & ML -> Agents -> Retail Distribution Analyst (or Snowflake Intelligence).
USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

CREATE OR REPLACE AGENT RIV2026DL_SNOW.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_AGENT
  COMMENT = 'Retail Distribution Analyst: sell-through, inventory and distribution insights across 12 retail trading partners'
  PROFILE = '{"display_name": "Retail Distribution Analyst"}'
  FROM SPECIFICATION
$$
{
  "models": {
    "orchestration": "auto"
  },
  "instructions": {
    "response": "You are a retail analytics assistant for a consumer brand that distributes apparel and footwear through 12 retail trading partners (big box, department store, discount, mall, outdoor, specialty, sports, luxury, shoe, European, British and Swiss retailers).\nLead with the direct answer in one or two sentences, then supporting detail. Format money as $ with thousands separators, rates as percentages with one decimal. State the week (period ending date) the answer covers.\nData caveats to mention when relevant: brand is mostly UNKNOWN in this data, so suggest department or category instead; each retailer reports a single channel (STORE or INTERNET), so channel comparisons are effectively retailer comparisons.\n",
    "orchestration": "Use retail_analyst for every data question about sales, margin, returns, markdowns, inventory, on order, in transit, receipts, return to vendor, shrink, sell-through, weeks of supply, stores, retailers, departments, categories or data freshness.\nInventory measures (on hand, on order, in transit) are snapshots: default to the latest week unless the user asks for a trend.\nWhen the result is a time trend or a ranking of several items, call data_to_chart to visualize it.\nIf a question is ambiguous (e.g. \"best\"), pick the most common retail interpretation, state it, and answer.\n",
    "sample_questions": [
      {
        "question": "What are net sales and margin % by department?"
      },
      {
        "question": "Which categories are overstocked based on weeks of supply?"
      },
      {
        "question": "Which retailers have the most units in transit right now?"
      },
      {
        "question": "Which 5 stores have the worst shrink?"
      },
      {
        "question": "Show the weekly net sales trend"
      },
      {
        "question": "How fresh is the data?"
      }
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "retail_analyst",
        "description": "Queries retail sell-through, inventory and distribution data for a brand selling through 12 retail partners. Covers net/gross sales, margin and margin %, customer returns and return rate, markdowns, on-hand, on-order and in-transit inventory, receipts, return-to-vendor, shrink (inventory adjustments), sell-through %, weeks of supply, average unit retail/cost. Dimensions: retailer, region, state, city, store, channel (STORE/INTERNET), comp store, climate, department, category, class, style, color, size, season, week ending date, plus data load freshness."
      }
    },
    {
      "tool_spec": {
        "type": "data_to_chart",
        "name": "data_to_chart",
        "description": "Generates visualizations from query results"
      }
    }
  ],
  "tool_resources": {
    "retail_analyst": {
      "semantic_view": "RIV2026DL_SNOW.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_SV",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "RIV_DEMO_WH"
      }
    }
  }
}
$$;
