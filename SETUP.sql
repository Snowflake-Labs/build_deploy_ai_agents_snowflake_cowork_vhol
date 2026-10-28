-- ====================================================================
-- MARKETING CAMPAIGNS ANALYTICS SYSTEM - COMPLETE SETUP SCRIPT
-- ====================================================================
-- This script creates a complete marketing campaigns analytics system with:
-- - Database and tables with sample data
-- - Semantic view for Cortex Analyst
-- - Cortex Search service for content discovery
-- - Agent skill (SKILL.md on a stage) for report generation
-- - Cortex Agent integrating all tools
--
-- Prerequisites:
-- - ACCOUNTADMIN role (or role with CREATE DATABASE privileges)
-- - Access to COWORK_AI_HOL_WH warehouse (or modify warehouse name below)
-- - SNOWFLAKE.CORTEX_USER database role granted
--
-- Estimated runtime: 5-10 minutes
-- ====================================================================

-- ====================================================================
-- SECTION 1: DATABASE AND SCHEMA CREATION
-- ====================================================================

-- Use ACCOUNTADMIN to setup
USE ROLE ACCOUNTADMIN;

-- --------------------------------------------------------------------
-- !! ACCOUNT-LEVEL PARAMETER CHANGE - REVIEW BEFORE RUNNING !!
-- --------------------------------------------------------------------
-- The MARKETING_AGENT created in Section 10 includes the web_search tool,
-- which requires Cortex web search to be enabled for the ENTIRE ACCOUNT.
-- This is not scoped to this lab: it allows any Cortex Agent / CoWork /
-- Cortex Code user in the account with web search configured to send
-- queries to an external web search provider. Confirm this aligns with
-- your organization's security and data governance policies first.
-- To skip, comment out the line below and remove the web_search tool from
-- the agent specification in Section 10. To revert after the lab:
--   ALTER ACCOUNT UNSET ENABLE_CORTEX_WEBSEARCH;
ALTER ACCOUNT SET ENABLE_CORTEX_WEBSEARCH = TRUE;

-- Create database using variable
CREATE DATABASE IF NOT EXISTS COWORK_AI_HOL_DB;
CREATE OR REPLACE SCHEMA COWORK_AI_HOL_DB.AGENTS;
USE SCHEMA COWORK_AI_HOL_DB.AGENTS;
CREATE WAREHOUSE IF NOT EXISTS COWORK_AI_HOL_WH WAREHOUSE_SIZE='SMALL';


-- ====================================================================
-- SECTION 2: NEW ROLE CONFIGURATION
-- ====================================================================

-- Create new role
CREATE OR REPLACE ROLE COWORK_AI_HOL_ROLE;

-- Set current user (or change if running on behalf of a coworker)
SET COWORK_AI_HOL_USER = CURRENT_USER();

-- Grant role to user
GRANT ROLE COWORK_AI_HOL_ROLE to USER IDENTIFIER($COWORK_AI_HOL_USER);

-- Usage on DB and Schema
GRANT USAGE ON DATABASE COWORK_AI_HOL_DB TO ROLE COWORK_AI_HOL_ROLE;
GRANT USAGE ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE TABLE ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE STAGE ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;


-- Specialized db/application roles
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE COWORK_AI_HOL_ROLE;
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE COWORK_AI_HOL_ROLE;

-- Required: enables access to CoCo 
GRANT DATABASE ROLE SNOWFLAKE.COPILOT_USER TO ROLE COWORK_AI_HOL_ROLE;

-- Create Datasets
GRANT CREATE FILE FORMAT ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE DATASET ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;

-- Create and execute tasks
GRANT CREATE TASK ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE COWORK_AI_HOL_ROLE;

-- Run evaluations
GRANT MONITOR ON FUTURE AGENTS IN SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;

-- Warehouse usage on COWORK_AI_HOL_WH and on User's defualt WH (which is used for eval tasks)
GRANT USAGE ON WAREHOUSE COWORK_AI_HOL_WH TO ROLE COWORK_AI_HOL_ROLE;

EXECUTE IMMEDIATE $$
DECLARE
    wh_name VARCHAR;
BEGIN
    EXECUTE IMMEDIATE 'DESC USER ' || CURRENT_USER();
    SELECT "value" INTO wh_name 
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) 
    WHERE "property" = 'DEFAULT_WAREHOUSE';
    
    EXECUTE IMMEDIATE 'GRANT USAGE ON WAREHOUSE ' || wh_name || ' TO ROLE COWORK_AI_HOL_ROLE';
    RETURN 'Granted USAGE on ' || wh_name;
END;
$$;

-- Git setup
GRANT CREATE API INTEGRATION ON ACCOUNT TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE GIT REPOSITORY ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;

-- Service and Agent creation
GRANT CREATE SEMANTIC VIEW ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE CORTEX SEARCH SERVICE ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;
GRANT CREATE AGENT ON SCHEMA COWORK_AI_HOL_DB.AGENTS TO ROLE COWORK_AI_HOL_ROLE;

-- ============================================================================
-- SECTION 3: CREATE GIT INTEGRATION (for loading CSV files from repo)
-- ============================================================================

-- Use new role
USE ROLE COWORK_AI_HOL_ROLE;

-- Lab code/data repo (Snowflake-Labs). If the repo moves, update BOTH
-- API_ALLOWED_PREFIXES and ORIGIN below - nothing else references the GitHub URL.
-- Create API integration for GitHub (public repo, no secrets needed)
CREATE OR REPLACE API INTEGRATION GIT_API_INTEGRATION_COWORK_AI_HOL
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs/')
    ENABLED = TRUE;

-- Clone the GitHub repository (lab data lives in the data/ folder at the repo root)
CREATE OR REPLACE GIT REPOSITORY CORTEX_AGENT_QUICKSTART_REPO
    API_INTEGRATION = GIT_API_INTEGRATION_COWORK_AI_HOL
    ORIGIN = 'https://github.com/Snowflake-Labs/build_deploy_ai_agents_snowflake_cowork_vhol.git';

-- Fetch latest from GitHub
ALTER GIT REPOSITORY CORTEX_AGENT_QUICKSTART_REPO FETCH;

-- Verify repository
SHOW GIT BRANCHES IN CORTEX_AGENT_QUICKSTART_REPO;
LS @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data;



-- ============================================================================
-- SECTION 4: CREATE AND POPULATE TABLES
-- ============================================================================

-- First create a file format to use when reading data from github
CREATE OR REPLACE FILE FORMAT AGENT_EVAL_QUICKSTART_CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMPRESSION = 'AUTO';


-- ============================================================================
-- CAMPAIGNS
-- ============================================================================
-- Create CAMPAIGNS table
CREATE OR REPLACE TABLE CAMPAIGNS (
    campaign_id INT,
    campaign_name VARCHAR(200) NOT NULL,
    campaign_type VARCHAR(50),
    start_date DATE,
    end_date DATE,
    budget_allocated DECIMAL(12,2),
    target_audience VARCHAR(200),
    channel VARCHAR(50),
    status VARCHAR(50),
    created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Populate CAMPAIGNS table
INSERT INTO CAMPAIGNS (campaign_id, campaign_name, campaign_type, start_date, end_date, budget_allocated, target_audience, channel, status, created_by)
SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10
FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGNS.csv (FILE_FORMAT=>AGENT_EVAL_QUICKSTART_CSV_FORMAT);

-- ============================================================================
-- CAMPAIGN_PERFORMANCE
-- ============================================================================
-- Create CAMPAIGN_PERFORMANCE table
CREATE OR REPLACE TABLE CAMPAIGN_PERFORMANCE (
    performance_id INT,
    campaign_id INT,
    date DATE,
    impressions INT,
    clicks INT,
    conversions INT,
    cost_per_click DECIMAL(10,4),
    cost_per_acquisition DECIMAL(10,2),
    revenue_generated DECIMAL(12,2),
    roi_percentage DECIMAL(8,2),
    engagement_rate DECIMAL(8,4)
    -- FOREIGN KEY (campaign_id) REFERENCES CAMPAIGNS(campaign_id)
);

-- Populate CAMPAIGN_PERFORMANCE table
INSERT INTO CAMPAIGN_PERFORMANCE (performance_id, campaign_id, date, impressions, clicks, conversions, cost_per_click, cost_per_acquisition, revenue_generated, roi_percentage, engagement_rate) 
SELECT $1, $2,$3,$4,$5, $6, $7, $8, $9, $10, $11
FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_PERFORMANCE.csv (FILE_FORMAT=>AGENT_EVAL_QUICKSTART_CSV_FORMAT);

-- ============================================================================
--CAMPAIGN_CONTENT
-- ============================================================================
-- Create CAMPAIGN_CONTENT table
CREATE OR REPLACE TABLE CAMPAIGN_CONTENT (
    campaign_id INT,
    content_type VARCHAR(100),
    campaign_description TEXT,
    marketing_copy TEXT,
    a_b_test_notes TEXT
    -- FOREIGN KEY (campaign_id) REFERENCES CAMPAIGNS(campaign_id)
);

-- Populate CAMPAIGN_CONTENT table
INSERT INTO CAMPAIGN_CONTENT (campaign_id, content_type, campaign_description, marketing_copy, a_b_test_notes)
SELECT $1, $2,$3,$4,$5 
FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_CONTENT.csv (FILE_FORMAT=>AGENT_EVAL_QUICKSTART_CSV_FORMAT);

-- ============================================================================
--CAMPAIGN_FEEDBACK
-- ============================================================================
-- Create CAMPAIGN_FEEDBACK table
CREATE OR REPLACE TABLE CAMPAIGN_FEEDBACK (
    feedback_id INT,
    campaign_id INT,
    feedback_date DATE,
    customer_segment VARCHAR(100),
    satisfaction_score DECIMAL(3,2),
    detailed_comments TEXT,
    survey_responses TEXT,
    recommended_improvements TEXT
    -- FOREIGN KEY (campaign_id) REFERENCES CAMPAIGNS(campaign_id)
);

-- Populate CAMPAIGN_FEEDBACK table
INSERT INTO CAMPAIGN_FEEDBACK (feedback_id, campaign_id, feedback_date, customer_segment, satisfaction_score, detailed_comments, survey_responses, recommended_improvements)
SELECT $1, $2,$3,$4,$5, $6, $7, $8
FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_FEEDBACK.csv (FILE_FORMAT=>AGENT_EVAL_QUICKSTART_CSV_FORMAT);

-- ============================================================================
--EVALS_TABLE
-- ============================================================================
-- Create EVALS_TABLE table
CREATE OR REPLACE TABLE EVALS_TABLE (
    INPUT_QUERY TEXT,
    GROUND_TRUTH_DATA VARCHAR);

-- Populate EVALS_TABLE table
INSERT INTO EVALS_TABLE (input_query, ground_truth_data)
SELECT $1, $2
FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/EVALS_TABLE.csv (FILE_FORMAT=>AGENT_EVAL_QUICKSTART_CSV_FORMAT);

CREATE OR REPLACE TABLE EVALS_TABLE
AS SELECT INPUT_QUERY, PARSE_JSON(GROUND_TRUTH_DATA) AS GROUND_TRUTH_DATA
FROM EVALS_TABLE;


-- ====================================================================
-- SECTION 5: VALIDATE DATA;
-- ====================================================================

SELECT * FROM CAMPAIGNS;

SELECT * FROM CAMPAIGN_CONTENT;

SELECT * FROM CAMPAIGN_FEEDBACK;

SELECT * FROM CAMPAIGN_PERFORMANCE;

SELECT * FROM EVALS_TABLE;

-- ====================================================================
-- SECTION 6: CREATE SEMANTIC VIEW
-- ====================================================================

CREATE OR REPLACE SEMANTIC VIEW MARKETING_PERFORMANCE_ANALYST
  TABLES (
    campaigns AS CAMPAIGNS PRIMARY KEY (campaign_id),
    performance AS CAMPAIGN_PERFORMANCE PRIMARY KEY (performance_id)
  )
  RELATIONSHIPS (
    performance(campaign_id) REFERENCES campaigns(campaign_id)
  )
  DIMENSIONS (
    PUBLIC campaigns.campaign_id AS campaign_id,
    PUBLIC campaigns.campaign_name AS campaign_name,
    PUBLIC campaigns.campaign_type AS campaign_type,
    PUBLIC campaigns.channel AS channel,
    PUBLIC campaigns.target_audience AS target_audience,
    PUBLIC campaigns.status AS status,
    PUBLIC campaigns.start_date AS start_date,
    PUBLIC campaigns.end_date AS end_date,
    PUBLIC campaigns.created_by AS created_by,
    PUBLIC performance.date AS date
  )
  METRICS (
    PUBLIC performance.total_revenue AS SUM(revenue_generated),
    PUBLIC performance.total_impressions AS SUM(impressions),
    PUBLIC performance.total_clicks AS SUM(clicks),
    PUBLIC performance.total_conversions AS SUM(conversions),
    PUBLIC performance.avg_cost_per_click AS AVG(cost_per_click),
    PUBLIC performance.avg_cost_per_acquisition AS AVG(cost_per_acquisition),
    PUBLIC performance.avg_roi AS AVG(roi_percentage),
    PUBLIC performance.avg_engagement_rate AS AVG(engagement_rate),
    PUBLIC campaigns.total_budget AS SUM(budget_allocated),
    PUBLIC campaigns.campaign_count AS COUNT(campaign_id)
  )
  COMMENT = 'Semantic view for analyzing marketing campaign performance and ROI';

-- Verify semantic view was created
SHOW SEMANTIC VIEWS LIKE 'MARKETING_PERFORMANCE_ANALYST';

-- ====================================================================
-- SECTION 7: CREATE CORTEX SEARCH SERVICE
-- ====================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE MARKETING_CAMPAIGNS_SEARCH
  ON combined_text
  ATTRIBUTES campaign_name, campaign_type, channel, content_type
  WAREHOUSE = COWORK_AI_HOL_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT 
      c.campaign_id,
      c.campaign_name,
      c.campaign_type,
      c.channel,
      cnt.content_type,
      CONCAT(
        'Campaign: ', c.campaign_name, '. ',
        'Type: ', c.campaign_type, '. ',
        'Channel: ', c.channel, '. ',
        'Description: ', cnt.campaign_description, '. ',
        'Marketing Copy: ', cnt.marketing_copy, '. ',
        'A/B Test Notes: ', cnt.a_b_test_notes
      ) as combined_text
    FROM CAMPAIGNS c
    JOIN CAMPAIGN_CONTENT cnt ON c.campaign_id = cnt.campaign_id
    
    UNION ALL
    
    SELECT 
      c.campaign_id,
      c.campaign_name,
      c.campaign_type,
      c.channel,
      'feedback' as content_type,
      CONCAT(
        'Campaign: ', c.campaign_name, '. ',
        'Customer Segment: ', fb.customer_segment, '. ',
        'Satisfaction Score: ', fb.satisfaction_score, '. ',
        'Comments: ', fb.detailed_comments, '. ',
        'Improvements: ', fb.recommended_improvements
      ) as combined_text
    FROM CAMPAIGNS c
    JOIN CAMPAIGN_FEEDBACK fb ON c.campaign_id = fb.campaign_id
  );

-- Verify search service was created
SHOW CORTEX SEARCH SERVICES LIKE 'MARKETING_CAMPAIGNS_SEARCH';

-- ====================================================================
-- SECTION 8: CREATE CAMPAIGN REPORT AGENT SKILL
-- ====================================================================
-- Instead of a stored procedure that hand-builds HTML, report generation is
-- packaged as an agent skill (SKILL.md) on a named stage. The agent reads the
-- skill on demand, gathers data with its Analyst/Search tools, and uses the
-- code execution sandbox to render the HTML report.

-- Named stage to host agent skills (one folder per skill, SKILL.md at its root)
CREATE OR REPLACE STAGE COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Internal stage hosting Cortex Agent skills';

-- Write SKILL.md to @AGENT_SKILLS/skills/campaign-report/ (no local PUT required)
COPY INTO @COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report/SKILL.md
FROM (SELECT $$---
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
FROM COWORK_AI_HOL_DB.AGENTS.CAMPAIGNS c
LEFT JOIN (
  SELECT campaign_id, SUM(impressions) AS impressions, SUM(clicks) AS clicks,
         SUM(conversions) AS conversions, SUM(revenue_generated) AS revenue,
         AVG(roi_percentage) AS avg_roi, AVG(cost_per_click) AS avg_cpc,
         AVG(cost_per_acquisition) AS avg_cpa, AVG(engagement_rate) AS avg_engagement_rate
  FROM COWORK_AI_HOL_DB.AGENTS.CAMPAIGN_PERFORMANCE
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
R=/snowflake/stages/cowork_ai_hol_db_agents_agent_skills/skills/campaign-report/render_report.py
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
$$)
FILE_FORMAT = (
  TYPE = CSV
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = NONE
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE
  COMPRESSION = NONE
  ENCODING = 'UTF8'
)
SINGLE = TRUE
OVERWRITE = TRUE
HEADER = FALSE;

-- Write the report renderer script used by the skill. Rendering HTML from a small JSON
-- payload with a pre-built script is much faster than having the agent hand-write HTML.
COPY INTO @COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report/render_report.py
FROM (SELECT $$"""Render a campaign report HTML file from a JSON data file.

Usage: python render_report.py <data.json> [output_dir]
Prints the path of the saved HTML file.
"""
import html
import json
import os
import sys
from datetime import datetime

CSS = (
    "body{font-family:Arial,sans-serif;margin:20px;color:#222}"
    "h1{margin-bottom:0}h2{margin-top:4px;color:#444}"
    "table{border-collapse:collapse;width:100%;margin:20px 0}"
    "th{background-color:#4CAF50;color:white;padding:10px;text-align:left}"
    "td{padding:10px}tr:nth-child(even){background-color:#f2f2f2}"
    ".card{border:1px solid #ccc;padding:10px;margin:10px 0}"
    ".muted{color:#666}footer{text-align:center;color:#666}"
)


def esc(value):
    return html.escape("" if value is None else str(value))


def num(value, decimals=0):
    if value is None:
        return "N/A"
    return f"{float(value):,.{decimals}f}"


def money(value):
    return "N/A" if value is None else "$" + num(value, 2)


def pct(value):
    return "N/A" if value is None else num(value, 2) + "%"


def ratio_pct(numer, denom):
    if not numer or not denom:
        return None
    return float(numer) / float(denom) * 100


def render(data):
    c = data.get("campaign", {})
    m = data.get("metrics", {})
    fb = data.get("feedback") or {}
    parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Campaign Report</title>",
        f"<style>{CSS}</style></head><body>",
        "<h1>Campaign Report</h1>",
        f"<h2>{esc(c.get('name'))}</h2>",
        "<h3>Campaign Overview</h3><table><tr><th>Attribute</th><th>Value</th></tr>",
    ]
    overview = [
        ("Campaign ID", esc(c.get("id"))),
        ("Type", esc(c.get("type"))),
        ("Channel", esc(c.get("channel"))),
        ("Duration", f"{esc(c.get('start_date'))} to {esc(c.get('end_date'))}"),
        ("Budget", money(c.get("budget"))),
        ("Target Audience", esc(c.get("target_audience"))),
        ("Status", esc(c.get("status"))),
    ]
    parts += [f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in overview]
    parts.append("</table>")

    engagement = m.get("avg_engagement_rate")
    metrics = [
        ("Total Impressions", num(m.get("impressions"))),
        ("Total Clicks", num(m.get("clicks"))),
        ("Total Conversions", num(m.get("conversions"))),
        ("Click-Through Rate", pct(ratio_pct(m.get("clicks"), m.get("impressions")))),
        ("Conversion Rate", pct(ratio_pct(m.get("conversions"), m.get("clicks")))),
        ("Average Cost Per Click", money(m.get("avg_cpc"))),
        ("Average Cost Per Acquisition", money(m.get("avg_cpa"))),
        ("Total Revenue Generated", money(m.get("revenue"))),
        ("Average ROI", pct(m.get("avg_roi"))),
        ("Average Engagement Rate", pct(None if engagement is None else float(engagement) * 100)),
    ]
    parts.append("<h3>Performance Metrics</h3><table><tr><th>Metric</th><th>Value</th></tr>")
    parts += [f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in metrics]
    parts.append("</table>")

    parts.append("<h3>Customer Feedback Summary</h3>")
    entries = sorted(fb.get("entries") or [], key=lambda e: str(e.get("date") or ""), reverse=True)
    if entries or fb.get("count"):
        parts.append(f"<p><strong>Average Satisfaction Score:</strong> {num(fb.get('avg_score'), 2)} / 5.0</p>")
        parts.append(f"<p><strong>Number of Feedback Entries:</strong> {num(fb.get('count') or len(entries))}</p>")
        for e in entries:
            parts.append(
                "<div class='card'>"
                + (f"<p class='muted'>{esc(e.get('date'))}</p>" if e.get("date") else "")
                + f"<p><strong>Segment:</strong> {esc(e.get('segment'))}</p>"
                + f"<p><strong>Score:</strong> {num(e.get('score'), 2)} / 5.0</p>"
                + f"<p><strong>Comments:</strong> {esc(e.get('comments'))}</p>"
                + f"<p><strong>Recommendations:</strong> {esc(e.get('improvements'))}</p></div>"
            )
    else:
        parts.append("<p>No feedback available</p>")

    insights = data.get("insights") or []
    if insights:
        parts.append("<h3>Key Insights</h3><ul>")
        parts += [f"<li>{esc(i)}</li>" for i in insights]
        parts.append("</ul>")

    external = data.get("external_context") or []
    if external:
        parts.append("<h3>External Context</h3><ul>")
        for x in external:
            source = esc(x.get("source"))
            url = x.get("url") or ""
            # Only plain http(s) links are rendered as hyperlinks
            if url.startswith(("http://", "https://")):
                source = f"<a href='{esc(url)}'>{source or esc(url)}</a>"
            parts.append(f"<li>{esc(x.get('text'))} <span class='muted'>({source})</span></li>")
        parts.append("</ul>")

    generated = datetime.now().strftime("%Y-%m-%d %H:%M")
    parts.append(f"<hr><footer>Report Generated: {generated}</footer></body></html>")
    return "".join(parts)


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: python render_report.py <data.json> [output_dir]")
    with open(sys.argv[1]) as f:
        data = json.load(f)
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "campaign_reports"
    os.makedirs(out_dir, exist_ok=True)
    campaign_id = str(data.get("campaign", {}).get("id", "UNKNOWN"))
    safe_id = "".join(ch for ch in campaign_id if ch.isalnum() or ch in "-_") or "UNKNOWN"
    path = os.path.join(out_dir, f"CAMPAIGN_{safe_id}_{datetime.now().strftime('%Y-%m-%d_%H_%M')}.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(data))
    print(os.path.abspath(path))


if __name__ == "__main__":
    main()
$$)
FILE_FORMAT = (
  TYPE = CSV
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = NONE
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE
  COMPRESSION = NONE
  ENCODING = 'UTF8'
)
SINGLE = TRUE
OVERWRITE = TRUE
HEADER = FALSE;

-- Verify the skill was uploaded
ALTER STAGE COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS REFRESH;
LS @COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report/;
-- ====================================================================
-- SECTION 9: TEST NEWLY CREATED SERVICES
-- ====================================================================

-- Simple campaign performance summary
-- Campaign performance by type


-- Test semantic view
SELECT 
    campaign_type,
    campaign_count,
    total_budget,
    total_revenue,
    avg_roi
FROM SEMANTIC_VIEW(
    MARKETING_PERFORMANCE_ANALYST
    DIMENSIONS campaign_type
    METRICS campaign_count, total_budget, total_revenue, avg_roi
);

-- Test search service
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'MARKETING_CAMPAIGNS_SEARCH',
        '{"query": "email campaigns", "columns": ["campaign_name", "campaign_type", "combined_text"], "limit": 3}'
    )
) as search_results;

-- Preview the campaign report skill content
SELECT $1 AS skill_md
FROM @COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report/SKILL.md
  (FILE_FORMAT => 'AGENT_EVAL_QUICKSTART_CSV_FORMAT')
LIMIT 5;

-- ====================================================================
-- SECTION 10: CREATE CORTEX AGENT
-- ====================================================================


CREATE OR REPLACE AGENT MARKETING_AGENT
WITH PROFILE='{ "display_name": "MARKETING_AGENT" }'
    COMMENT=$$ Agent specializing in analyzing marketing campaigns for performance, ROI, feedback, etc. $$
FROM SPECIFICATION $$
{
    "models": {"orchestration": "claude-sonnet-5"},
    "instructions": {
        "orchestration": "",
        "response": "",
        "sample_questions": [
      {
        "question": "What campaigns have the highest ROI?"
      }
    ]
    },
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "query_performance_metrics",
                "description": "Query structured performance data including campaign ROI, revenue, budget efficiency, impressions, clicks, conversions, cost metrics, and engagement rates. Use for quantitative analysis of campaign performance across channels and time periods."
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "search_campaign_content",
                "description": "Search unstructured campaign content including campaign descriptions, marketing copy, A/B test results, customer feedback, and recommended improvements. Use for qualitative insights, content discovery, and learning from past campaigns."
            }
        },
        {
            "tool_spec": {
                "type": "code_execution",
                "name": "code_execution"
            }
        },
        {
            "tool_spec": {
                "type": "web_search",
                "name": "web_search"
            }
        }
    ],
    "skills": [
        {
            "name": "campaign-report",
            "source": {
                "type": "STAGE",
                "path": "@COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report"
            }
        }
    ],
    "tool_resources": {
        "query_performance_metrics": {
            "execution_environment": {
                "query_timeout": 299,
                "type": "warehouse",
                "warehouse": "COWORK_AI_HOL_WH"
            },
            "semantic_view": "COWORK_AI_HOL_DB.AGENTS.MARKETING_PERFORMANCE_ANALYST"
        },
        "search_campaign_content": {
            "execution_environment": {
                "query_timeout": 299,
                "type": "warehouse",
                "warehouse": "COWORK_AI_HOL_WH"
            },
            "search_service": "COWORK_AI_HOL_DB.AGENTS.MARKETING_CAMPAIGNS_SEARCH"
        },
        "code_execution": {
            "permission_policy": {
                "type": "always_allow"
            }
        }
    }
}

$$;
-- Validate agent creation
DESCRIBE AGENT MARKETING_AGENT;

-- Grant usage, modify, monitor on agent to accountadmin
GRANT MONITOR ON AGENT MARKETING_AGENT to ROLE ACCOUNTADMIN;

-- ====================================================================
-- SECTION 10.5: EXPLORE AGENT VERSIONS
-- ====================================================================
-- CREATE AGENT automatically creates two versions:
--   VERSION$1 (committed, immutable snapshot of the baseline spec)
--   LIVE (mutable working copy for development)

-- View all versions
SHOW VERSIONS IN AGENT MARKETING_AGENT;

-- Assign a human-readable alias to the baseline version
ALTER AGENT MARKETING_AGENT
  MODIFY VERSION VERSION$1 SET ALIAS = baseline;

-- The default version is VERSION$1 (latest committed = LAST)
-- The baseline eval in Section 12 will run against this version
SHOW VERSIONS IN AGENT MARKETING_AGENT;


-- ====================================================================
-- SECTION 11: OPTIONAL - UI DRIVEN AGENT EVALUATIONS 
-- ====================================================================


SELECT 
$$
Optionally follow the below instructions to use the Agents UI to evaluate the performance of your new agent! Note we will programmatically execute evaluations in Section 12. 

- Navigate to your newly created agent and click into Evaluations Tab
    - Name your new evaluation run and optionally give a description [click next]
    - Select Create New Dataset
        - Select COWORK_AI_HOL_DB.AGENTS.EVALS_TABLE as your input table
        - Select COWORK_AI_HOL_DB.AGENTS.QUICKSTART_EVALSET as your new dataset destination [click next]
    - Select INPUT_QUERY as your Query Text column
        - Check boxes for all metrics available
        - Tool Selection Accuracy, Tool Execution Accuracy, and Answer Correctness should reference the EXPECTED_TOOLS column
        - Click Create Evaluation
        
Now wait as your queries are executed and your evaluation metrics are computed! This should populate in roughly ~3-5 minutes.

Compare how the baseline agent and the optimized agent performed on various metrics!

====================================================================
$$ as setup_status;

-- ====================================================================
-- SECTION 12: AGENT EVALUATION
-- ====================================================================

-- First we will create a dataset to use for evaluating our agent
CALL SYSTEM$CREATE_EVALUATION_DATASET(
    'Cortex Agent',
    'COWORK_AI_HOL_DB.AGENTS.EVALS_TABLE',
    'COWORK_AI_HOL_DB.AGENTS.MARKETING_CAMPAIGN_EVALSET',
    OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH_DATA'));


-- Confirm dataset creation
SHOW DATASETS;

-- Next we will create a stage to store our evaluation config file
CREATE OR REPLACE STAGE COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Internal stage to host evaluation config files';

-- Copy file from git repo to stage
-- COPY FILES INTO @COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE
-- FROM @CORTEX_AGENT_QUICKSTART_REPO/branches/main/
-- FILES = ('marketing_campaign_eval_config.yaml');


-- Write eval config YAML with correct schema references
-- (We inline it rather than copying from git so the schema path is correct)
CREATE OR REPLACE TEMPORARY TABLE temp_eval_config (content VARCHAR);
INSERT INTO temp_eval_config VALUES (
'# Marketing Campaign Agent Evaluation Configuration
# Evaluation metrics for answer correctness, logical consistency, tool selection accuracy,
# execution efficiency and groundedness
# Based on TruLens Agent GPA evaluation methodology

# Evaluation task configuration
evaluation:
  agent_params:
    agent_name: COWORK_AI_HOL_DB.AGENTS.MARKETING_AGENT
    agent_type: CORTEX AGENT
    agent_version: VERSION$1
  run_params:
    label: Marketing Campaign Agent Evaluation
    description: Evaluating Answer Correctness, Logical Consistency, Tool Selection Accuracy, Tool Execution Accuracy, Groundedness and Execution Efficiency metrics for the marketing campaign analytics agent
  source_metadata:
    type: dataset
    dataset_name: COWORK_AI_HOL_DB.AGENTS.MARKETING_CAMPAIGN_EVALSET

metrics:
  # Built-in metrics
  - name: "answer_correctness"
    version: "v3"
  - name: "logical_consistency"
    version: "v3"
  - name: "tool_selection_accuracy"
    version: "v3"
  - name: "tool_execution_accuracy"
    version: "v3"

  # Custom Metrics

  # Groundedness metric - TruLens Agent GPA based evaluation
  # Evaluates whether the agent''s response is supported by the execution trace
  - name: groundedness
    model: "claude-sonnet-4-6"
    score_ranges:
      min_score: [0, 0.33]
      median_score: [0.34, 0.66]
      max_score: [0.67, 1]
    prompt: |
      You are evaluating the groundedness of an AI agent''s response. Groundedness measures
      whether each substantive claim in the response is supported by concrete evidence in
      the execution trace.

      IMPORTANT: Evaluate claim-to-result alignment, not claim-to-tool-type alignment.
      A claim is grounded only if the required evidence appears in actual tool outputs,
      retrieved rows/snippets, report outputs, or other trace context.

      Agent Response to Evaluate:
      {{output}}

      The complete agent execution trace is provided as context, including:
      - All tool calls made (query_performance_metrics, search_campaign_content, web_search)
      - Tool outputs and retrieved data
      - Intermediate reasoning steps

      Here are a few examples of groundedness scores:

      0 (Not Grounded):
        - Key claims are unsupported, contradicted, or fabricated relative to tool results
        - Superlative/comparative conclusions ("most compelling", "most alike", "best")
          are made without evidence from returned results
        - Report responses invent artifact details, KPIs, or findings not present in outputs

      0.5 (Partially Grounded):
        - Some important claims are evidence-backed, but at least one material conclusion
          is weakly supported or not directly shown in results
        - Comparison conclusion is plausible but incomplete (limited evidence or missing tie-break rationale)
        - Report output details are partially accurate but omit or blur key result-backed facts

      1 (Fully Grounded):
        - All material claims are traceable to concrete evidence in tool results
        - Metrics, campaign attributes, and report details match retrieved outputs
        - Comparative/superlative conclusions are justified using explicit evidence
        - When evidence is incomplete, the response states uncertainty instead of guessing

      Consider:
      - Are revenue figures, ROI percentages, and other metrics supported by result rows?
      - Are campaign descriptions, A/B notes, and feedback grounded in returned snippets?
      - For report requests, does the response accurately reflect report generation output
        (artifact/link/name) and avoid fabricated details?
      - For capability/meta queries, tool calls may be unnecessary; still require claims
        to align with supported behavior and trace context, without over-claiming.

  # Execution Efficiency metric - TruLens Agent GPA based evaluation
  # Evaluates how optimally the agent uses its available tools to accomplish the user''s goal
  - name: execution_efficiency
    model: "claude-sonnet-4-6"
    score_ranges:
      min_score: [0, 0.33]
      median_score: [0.34, 0.66]
      max_score: [0.67, 1]
    prompt: |
      You are evaluating the execution efficiency of an AI agent that analyzes marketing
      campaigns. Execution efficiency measures how optimally the agent uses its available
      tools to accomplish the user''s goal.

      The agent has access to the following tools:
      1. query_performance_metrics - For quantitative analysis (revenue, ROI, conversions, etc.)
      2. search_campaign_content - For qualitative insights (descriptions, feedback, A/B tests)
      3. web_search - For external/industry context
      Report requests are handled by the campaign-report skill, which is not a tool call; it uses the tools above to gather data.

      Analyze the complete agent execution trace provided as context, including:
      - Execution duration: {{duration}} milliseconds
      - Tool calls made and their sequence
      - Any errors encountered: {{error}}
      - Execution status: {{status}}

      Here are a few examples of execution efficiency scores:

      0 (Inefficient):
        - Excessive or redundant tool calls relative to query complexity
        - Repeated broad searches when one or two focused retrievals would suffice
        - Multiple avoidable retries, loops, or backtracking steps
        - Very long execution duration without proportional complexity
        - Unnecessary tool chains for capability/meta questions

      0.5 (Moderately Efficient):
        - Reasonable path but with one notable inefficiency
        - Slightly more calls than necessary, or avoidable duplicate retrieval
        - Mostly direct flow with minor backtracking

      1 (Highly Efficient):
        - Minimal sensible path from request to answer
        - Tool sequence is concise and dependency-aware
        - No redundant retrievals or unnecessary calls
        - Execution time is appropriate for task complexity

      Consider:
      - For report requests, was the flow efficient (identify campaign if needed ->
        generate report -> optional concise support fetch)?
      - For vague comparison questions, did the agent avoid repeated unfocused searches?
      - For capability/meta queries, did it avoid unnecessary tool execution?
      - Could the same result have been achieved with fewer calls or a tighter sequence?
      - Focus on path efficiency and redundancy, not factual claim support.
');

CREATE OR REPLACE FILE FORMAT yaml_format
  TYPE = 'CSV'
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = NONE
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE
  COMPRESSION = NONE;

COPY INTO @EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml
FROM (SELECT content FROM temp_eval_config)
FILE_FORMAT = yaml_format
SINGLE = TRUE
OVERWRITE = TRUE
HEADER = FALSE;

DROP TABLE temp_eval_config;

DESCRIBE STAGE eval_config_stage;

-- Confirm yaml was uploaded
LS @COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE;

-- Check contents of yaml
SELECT $1 FROM @COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml;

-- Kickoff evaluation run using yaml config
CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'BASELINE_MARKETING_AGENT_EVAL_RUN'),
  '@COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml'
);


-- Check status of evaluation run
CALL EXECUTE_AI_EVALUATION( 
  'STATUS',
  OBJECT_CONSTRUCT('run_name', 'BASELINE_MARKETING_AGENT_EVAL_RUN'),
  '@COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml'
);

-- Iteratively check status of evaluation run and wait to proceed until eval is completed

DECLARE
    run_name VARCHAR DEFAULT 'BASELINE_MARKETING_AGENT_EVAL_RUN';
    config_path VARCHAR DEFAULT '@COWORK_AI_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml';
    max_wait_seconds NUMBER DEFAULT 600;
    poll_interval_seconds NUMBER DEFAULT 20;
    status_val VARCHAR;
    elapsed NUMBER DEFAULT 0;
BEGIN
    LOOP
        CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', :run_name), :config_path);
        LET status_cursor CURSOR FOR SELECT STATUS FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        OPEN status_cursor;
        FETCH status_cursor INTO status_val;
        CLOSE status_cursor;
        
        IF (status_val = 'COMPLETED') THEN
            RETURN 'COMPLETED after ' || :elapsed || ' seconds';
        ELSEIF (status_val IN ('FAILED', 'ERROR')) THEN
            RETURN 'FAILED';
        ELSEIF (status_val = 'CANCELLED') THEN
            RETURN 'CANCELLED';
        END IF;
        
        IF (elapsed >= :max_wait_seconds) THEN
            RETURN 'TIMEOUT after ' || :max_wait_seconds || ' seconds';
        END IF;
        
        CALL SYSTEM$WAIT(:poll_interval_seconds);
        elapsed := elapsed + :poll_interval_seconds;
    END LOOP;
END;

SELECT 'SETUP COMPLETE! Access your evaluation results at link below';
SELECT 'https://app.snowflake.com/' || 
       LOWER(CURRENT_ORGANIZATION_NAME()) || '/' || 
       LOWER(CURRENT_ACCOUNT_NAME()) || 
       '/#/agents/database/COWORK_AI_HOL_DB/schema/AGENTS/agent/MARKETING_AGENT/details?tab=evaluations&preset=PRESET_LAST_DAY&type=relative' 
       AS agent_eval_url;
