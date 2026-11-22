---
name: campaign-report
description: Generate a comprehensive, presentation-ready HTML report for a specific marketing campaign, covering campaign details, performance metrics (impressions, clicks, conversions, CTR, conversion rate, CPC, CPA, revenue, ROI, engagement), and customer feedback. Use when the user asks to create, build, generate, or export a report for a campaign.
---

# Campaign Report

Produce a single self-contained HTML report for one campaign. A ready-made renderer,
`render_report.py`, ships with this skill and handles all HTML layout, styling, number
formatting, CTR/conversion-rate math, and HTML escaping. Do NOT write HTML yourself.

Target path: 2 data calls (in parallel) -> 1 code execution -> answer.

## 1. Gather the data - ONE parallel step
Issue both calls in the same step. Identify the campaign by ID or name inside the calls
themselves; do not run a separate lookup first.

`query_performance_metrics` - get everything with ONE query. Run this SQL as-is, changing
only the WHERE clause (use `c.campaign_id = <id>` or `c.campaign_name ILIKE '%<name>%'`).
Do not rewrite it with semantic-view metric names (TOTAL_BUDGET, TOTAL_IMPRESSIONS, etc.)
as columns - they are not columns and will fail.

```sql
SELECT c.campaign_id, c.campaign_name, c.campaign_type, c.channel, c.start_date, c.end_date,
       c.target_audience, c.status, c.budget_allocated AS budget,
       p.impressions, p.clicks, p.conversions, p.revenue, p.avg_roi, p.avg_cpc, p.avg_cpa,
       p.avg_engagement_rate
FROM AI_AGENT_HOL_DB.DATA.CAMPAIGNS c
LEFT JOIN (
  SELECT campaign_id, SUM(impressions) AS impressions, SUM(clicks) AS clicks,
         SUM(conversions) AS conversions, SUM(revenue_generated) AS revenue,
         AVG(roi_percentage) AS avg_roi, AVG(cost_per_click) AS avg_cpc,
         AVG(cost_per_acquisition) AS avg_cpa, AVG(engagement_rate) AS avg_engagement_rate
  FROM AI_AGENT_HOL_DB.DATA.CAMPAIGN_PERFORMANCE
  GROUP BY campaign_id
) p ON p.campaign_id = c.campaign_id
WHERE c.campaign_name ILIKE '%<campaign name>%';
```

`search_campaign_content` - one search with the campaign name in the query (filter on
CAMPAIGN_NAME if known; there is no CAMPAIGN_ID filter), asking for customer feedback
(segment, satisfaction score, comments, recommended improvements) and A/B test notes.

If the campaign is ambiguous (several matches or none), ask the user which one they mean.
Only retry a call if it errored; fix the specific issue once.

## 2. Optional market context
Only if the user asks for benchmarks or industry context, add one `web_search` call to
the step above and include the results under `external_context`.

## 3. Render with ONE `code_execution` call
In a single script, write the JSON below to `report_data.json` and run the renderer. It
saves straight to `/workspace/campaign_reports/`, so do not copy or move the file. The
renderer is mounted read-only at the path below; the `find` fallback only runs if it moved.
Do not run a separate command to locate it.

```bash
cat > report_data.json << 'EOF'
{
  "campaign": {"id": 8, "name": "...", "type": "...", "channel": "...",
               "start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD", "budget": 150000,
               "target_audience": "...", "status": "..."},
  "metrics": {"impressions": 0, "clicks": 0, "conversions": 0, "revenue": 0.0,
              "avg_roi": 0.0, "avg_cpc": 0.0, "avg_cpa": 0.0, "avg_engagement_rate": 0.0},
  "feedback": {"avg_score": 0.0, "count": 0,
               "entries": [{"date": "", "segment": "", "score": 0.0,
                            "comments": "", "improvements": ""}]},
  "insights": ["3-5 bullet points derived strictly from the data above"],
  "external_context": [{"text": "", "source": "", "url": ""}]
}
EOF
R=/snowflake/stages/ai_agent_hol_db_agents_agent_skills/skills/campaign-report/render_report.py
[ -f "$R" ] || R=$(find / -name render_report.py -path '*campaign-report*' 2>/dev/null | head -1)
python3 "$R" report_data.json /workspace/campaign_reports
```

Field rules:
- Use raw numbers from tool results (no `$`, `%`, or commas). `avg_roi` is a percent
  value (e.g. 142.46); `avg_engagement_rate` is a fraction (e.g. 0.052).
- Use `null` for any value the tools did not return; omit `feedback` if there is none,
  and omit `external_context` unless web search was used.
- Only include values returned by the tools - never invent numbers.

The script prints the saved file path. Do not re-open, list, or validate the file
afterwards - a printed path means success.

Then call `present_file` ONCE with that path so the user can download the report. If it
returns an error, do not retry - just give the saved path in your answer.

## 4. Respond
State the saved file path, the headline metrics (impressions, clicks, conversions, CTR,
conversion rate, revenue, ROI), and the same 3-5 key insights. Keep it concise.
