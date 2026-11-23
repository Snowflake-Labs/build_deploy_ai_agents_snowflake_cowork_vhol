-- ====================================================================
-- post_deploy.sql - run AFTER the DCM deploy, as ACCOUNTADMIN, from the Snowsight
-- Workspace (Run All). Covers what DCM cannot DEFINE: git repo, data loads,
-- stage files, Cortex Search service, Cortex Agent + version alias,
-- eval datasets + baseline run, future grants and SNOWFLAKE roles.
-- Re-runnable: loads TRUNCATE first; the agent is only created if missing.
-- ====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE AI_AGENT_HOL_WH;

-- Lab role for the person running the lab
SET LAB_USER = CURRENT_USER();
GRANT ROLE AI_AGENT_HOL_ROLE TO USER IDENTIFIER($LAB_USER);

-- Grants DCM does not manage (SNOWFLAKE roles, future grants)
GRANT DATABASE ROLE SNOWFLAKE.COPILOT_USER TO ROLE AI_AGENT_HOL_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AI_AGENT_HOL_ROLE;
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE AI_AGENT_HOL_ROLE;
GRANT MONITOR ON FUTURE AGENTS IN SCHEMA AI_AGENT_HOL_DB.AGENTS TO ROLE AI_AGENT_HOL_ROLE;
GRANT MONITOR ON FUTURE AGENTS IN SCHEMA AI_AGENT_HOL_DB.AGENTS TO ROLE ACCOUNTADMIN;

-- --------------------------------------------------------------------
-- Git repository + data loads
-- --------------------------------------------------------------------
CREATE OR REPLACE GIT REPOSITORY AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO
    API_INTEGRATION = GIT_API_INTEGRATION_AI_AGENT_HOL
    ORIGIN = 'https://github.com/Snowflake-Labs/build_deploy_ai_agents_snowflake_cowork_vhol.git';
ALTER GIT REPOSITORY AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO FETCH;

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.CAMPAIGNS;
INSERT INTO AI_AGENT_HOL_DB.DATA.CAMPAIGNS (campaign_id, campaign_name, campaign_type, start_date, end_date, budget_allocated, target_audience, channel, status, created_by)
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGNS.csv (FILE_FORMAT => 'AI_AGENT_HOL_DB.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT');

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.CAMPAIGN_PERFORMANCE;
INSERT INTO AI_AGENT_HOL_DB.DATA.CAMPAIGN_PERFORMANCE (performance_id, campaign_id, date, impressions, clicks, conversions, cost_per_click, cost_per_acquisition, revenue_generated, roi_percentage, engagement_rate)
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_PERFORMANCE.csv (FILE_FORMAT => 'AI_AGENT_HOL_DB.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT');

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.CAMPAIGN_CONTENT;
INSERT INTO AI_AGENT_HOL_DB.DATA.CAMPAIGN_CONTENT (campaign_id, content_type, campaign_description, marketing_copy, a_b_test_notes)
SELECT $1, $2, $3, $4, $5
FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_CONTENT.csv (FILE_FORMAT => 'AI_AGENT_HOL_DB.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT');

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.CAMPAIGN_FEEDBACK;
INSERT INTO AI_AGENT_HOL_DB.DATA.CAMPAIGN_FEEDBACK (feedback_id, campaign_id, feedback_date, customer_segment, satisfaction_score, detailed_comments, survey_responses, recommended_improvements)
SELECT $1, $2, $3, $4, $5, $6, $7, $8
FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/CAMPAIGN_FEEDBACK.csv (FILE_FORMAT => 'AI_AGENT_HOL_DB.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT');

-- Dev / held-out split (10 / 5). One held-out question per question type:
-- report, multi-dimension analytics, superlative quant+qual, out-of-scope refusal, web search.
-- Tune instructions on DEV only; HOLDOUT decides whether a candidate version is promoted.
-- NOTE: 15 rows is teaching-sized; production evals typically need far more rows per split.
TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.EVALS_TABLE;
INSERT INTO AI_AGENT_HOL_DB.DATA.EVALS_TABLE (input_query, ground_truth_data, split)
SELECT $1, PARSE_JSON($2),
    CASE
        WHEN $1 ILIKE 'Generate a report for campaign #12%'
          OR $1 ILIKE 'What''s the relationship between campaign duration%'
          OR $1 ILIKE 'For the campaign with the highest engagement%'
          OR $1 ILIKE 'How many iphones%'
          OR $1 ILIKE 'Based on Pew Research Center%'
        THEN 'HOLDOUT'
        ELSE 'DEV'
    END
FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/data/EVALS_TABLE.csv (FILE_FORMAT => 'AI_AGENT_HOL_DB.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT');

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.EVALS_TABLE_DEV;
INSERT INTO AI_AGENT_HOL_DB.DATA.EVALS_TABLE_DEV (input_query, ground_truth_data)
SELECT input_query, ground_truth_data FROM AI_AGENT_HOL_DB.DATA.EVALS_TABLE WHERE split = 'DEV';

TRUNCATE TABLE AI_AGENT_HOL_DB.DATA.EVALS_TABLE_HOLDOUT;
INSERT INTO AI_AGENT_HOL_DB.DATA.EVALS_TABLE_HOLDOUT (input_query, ground_truth_data)
SELECT input_query, ground_truth_data FROM AI_AGENT_HOL_DB.DATA.EVALS_TABLE WHERE split = 'HOLDOUT';

-- --------------------------------------------------------------------
-- Agent skill + eval configs, copied from the lab Git repo
-- --------------------------------------------------------------------
COPY FILES INTO @AI_AGENT_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report/
    FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/dcm_project/files/skills/campaign-report/
    FILES = ('SKILL.md', 'render_report.py');
COPY FILES INTO @AI_AGENT_HOL_DB.AGENTS.EVAL_CONFIG_STAGE
    FROM @AI_AGENT_HOL_DB.DATA.CORTEX_AGENT_QUICKSTART_REPO/branches/main/dcm_project/files/evals/
    FILES = ('marketing_campaign_eval_config.yaml',
             'marketing_campaign_eval_config_dev_candidate.yaml',
             'marketing_campaign_eval_config_holdout_baseline.yaml',
             'marketing_campaign_eval_config_holdout_candidate.yaml');
ALTER STAGE AI_AGENT_HOL_DB.AGENTS.AGENT_SKILLS REFRESH;
ALTER STAGE AI_AGENT_HOL_DB.AGENTS.EVAL_CONFIG_STAGE REFRESH;

-- --------------------------------------------------------------------
-- Objects owned by the lab role
-- --------------------------------------------------------------------
USE ROLE AI_AGENT_HOL_ROLE;
USE WAREHOUSE AI_AGENT_HOL_WH;

CREATE OR REPLACE CORTEX SEARCH SERVICE AI_AGENT_HOL_DB.ANALYTICS.MARKETING_CAMPAIGNS_SEARCH
  ON combined_text
  ATTRIBUTES campaign_name, campaign_type, channel, content_type
  WAREHOUSE = AI_AGENT_HOL_WH
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
    FROM AI_AGENT_HOL_DB.DATA.CAMPAIGNS c
    JOIN AI_AGENT_HOL_DB.DATA.CAMPAIGN_CONTENT cnt ON c.campaign_id = cnt.campaign_id
    
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
    FROM AI_AGENT_HOL_DB.DATA.CAMPAIGNS c
    JOIN AI_AGENT_HOL_DB.DATA.CAMPAIGN_FEEDBACK fb ON c.campaign_id = fb.campaign_id
  );

-- IF NOT EXISTS: re-deploying keeps VERSION$2+ committed during the lab.
-- To reset to the baseline, DROP AGENT AI_AGENT_HOL_DB.AGENTS.MARKETING_AGENT and re-deploy.
CREATE AGENT IF NOT EXISTS AI_AGENT_HOL_DB.AGENTS.MARKETING_AGENT
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
                "path": "@AI_AGENT_HOL_DB.AGENTS.AGENT_SKILLS/skills/campaign-report"
            }
        }
    ],
    "tool_resources": {
        "query_performance_metrics": {
            "execution_environment": {
                "query_timeout": 299,
                "type": "warehouse",
                "warehouse": "AI_AGENT_HOL_WH"
            },
            "semantic_view": "AI_AGENT_HOL_DB.ANALYTICS.MARKETING_PERFORMANCE_ANALYST"
        },
        "search_campaign_content": {
            "execution_environment": {
                "query_timeout": 299,
                "type": "warehouse",
                "warehouse": "AI_AGENT_HOL_WH"
            },
            "search_service": "AI_AGENT_HOL_DB.ANALYTICS.MARKETING_CAMPAIGNS_SEARCH"
        },
        "code_execution": {
            "permission_policy": {
                "type": "always_allow"
            }
        }
    }
}

$$;

ALTER AGENT AI_AGENT_HOL_DB.AGENTS.MARKETING_AGENT
  MODIFY VERSION VERSION$1 SET ALIAS = baseline;

USE ROLE ACCOUNTADMIN;
GRANT MONITOR ON AGENT AI_AGENT_HOL_DB.AGENTS.MARKETING_AGENT TO ROLE ACCOUNTADMIN;
USE ROLE AI_AGENT_HOL_ROLE;

-- Evaluation datasets: DEV (tune) and HOLDOUT (decide). Only the DEV baseline runs here;
-- held-out runs wait until a candidate is frozen (see evaluate_holdout.sql).
CALL SYSTEM$CREATE_EVALUATION_DATASET(
    'Cortex Agent',
    'AI_AGENT_HOL_DB.DATA.EVALS_TABLE_DEV',
    'AI_AGENT_HOL_DB.AGENTS.MARKETING_CAMPAIGN_EVALSET_DEV',
    OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH_DATA'));

CALL SYSTEM$CREATE_EVALUATION_DATASET(
    'Cortex Agent',
    'AI_AGENT_HOL_DB.DATA.EVALS_TABLE_HOLDOUT',
    'AI_AGENT_HOL_DB.AGENTS.MARKETING_CAMPAIGN_EVALSET_HOLDOUT',
    OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH_DATA'));

USE SCHEMA AI_AGENT_HOL_DB.AGENTS;
CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'MARKETING_AGENT_V1_DEV_R01'),
  '@AI_AGENT_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config.yaml'
);
