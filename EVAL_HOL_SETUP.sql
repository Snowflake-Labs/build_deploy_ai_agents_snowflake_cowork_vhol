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

-- Create API integration for GitHub (public repo, no secrets needed)
CREATE API INTEGRATION IF NOT EXISTS GIT_API_INTEGRATION_COWORK_AI_HOL
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-ebotwick/')
    ENABLED = TRUE;

-- Clone the GitHub repository (lab data lives in the data/ folder at the repo root)
CREATE OR REPLACE GIT REPOSITORY CORTEX_AGENT_QUICKSTART_REPO
    API_INTEGRATION = GIT_API_INTEGRATION_COWORK_AI_HOL
    ORIGIN = 'https://github.com/sfc-gh-ebotwick/build_deploy_ai_agents_snowflake_cowork_vhol.git';

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

Produce a single self-contained HTML report for one campaign.

## 1. Identify the campaign
- The user may give a campaign ID or a campaign name. If only a name is given, use
  `query_performance_metrics` to resolve it to a campaign ID.
- If the request is ambiguous (several matching campaigns, or none specified), ask the
  user which campaign they mean before continuing.

## 2. Gather the data (use the SQL tools, not the sandbox)
Use `query_performance_metrics` to retrieve:
- Campaign details: name, type, channel, start/end date, budget allocated, target audience, status.
- Aggregated performance: total impressions, clicks, conversions, revenue generated;
  CTR = clicks / impressions; conversion rate = conversions / clicks;
  average cost per click, average cost per acquisition, average ROI %, average engagement rate.

Use `search_campaign_content` (filtered to the campaign) to retrieve:
- Customer feedback: average satisfaction score (out of 5), number of feedback entries,
  and the most recent entries with customer segment, score, detailed comments, and
  recommended improvements.
- Notable content such as A/B test results or campaign description.

Only report values returned by the tools. If a section has no data, say so in the report
(e.g. "No feedback available") rather than inventing numbers.

## 3. Optional market context
If the user asks for benchmarks or industry context, use `web_search` and cite the
sources in a clearly labeled "External Context" section. Keep it separate from campaign data.

## 4. Render the report with `code_execution`
Write a Python script in the sandbox that builds the HTML from the retrieved results and
saves it to the workspace as `campaign_reports/CAMPAIGN_<id>_<YYYY-MM-DD_HH_MM>.html`.

Report layout:
1. Title "Campaign Report" and campaign name
2. Campaign overview (type, channel, duration, budget, audience, status)
3. Performance metrics table (Metric | Value), numbers formatted with thousands
   separators, currency with `$` and 2 decimals, rates as percentages with 2 decimals
4. Customer feedback summary followed by individual feedback cards (newest first)
5. Key insights: 3-5 bullet points derived strictly from the data above
6. Footer with the generation timestamp

Styling: inline `<style>` only (Arial/sans-serif, 20px margin, header row background
`#4CAF50` with white text, zebra-striped rows). No external CSS, JS, fonts, or images.
HTML-escape all text that came from the data.

## 5. Respond
Summarize the headline metrics and insights in the chat, and give the path of the saved
HTML file so the user can open or download it.
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
LS @COWORK_AI_HOL_DB.AGENTS.AGENT_SKILLS PATTERN = '.*SKILL\\.md';
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
      - All tool calls made (query_performance_metrics, search_campaign_content, code_execution, web_search, campaign-report skill)
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

      The agent has access to the following tools and skills:
      1. query_performance_metrics - For quantitative analysis (revenue, ROI, conversions, etc.)
      2. search_campaign_content - For qualitative insights (descriptions, feedback, A/B tests)
      3. campaign-report skill (via code_execution) - For creating comprehensive HTML reports
      4. web_search - For external/industry context

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
