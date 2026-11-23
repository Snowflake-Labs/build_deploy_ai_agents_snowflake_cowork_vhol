-- Campaign tables. Data is loaded in post_deploy.sql.

DEFINE TABLE {{db}}.DATA.CAMPAIGNS (
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

DEFINE TABLE {{db}}.DATA.CAMPAIGN_PERFORMANCE (
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
);

DEFINE TABLE {{db}}.DATA.CAMPAIGN_CONTENT (
    campaign_id INT,
    content_type VARCHAR(100),
    campaign_description TEXT,
    marketing_copy TEXT,
    a_b_test_notes TEXT
);

DEFINE TABLE {{db}}.DATA.CAMPAIGN_FEEDBACK (
    feedback_id INT,
    campaign_id INT,
    feedback_date DATE,
    customer_segment VARCHAR(100),
    satisfaction_score DECIMAL(3,2),
    detailed_comments TEXT,
    survey_responses TEXT,
    recommended_improvements TEXT
);

-- Original script loaded VARCHAR then CTAS'd to VARIANT; defined directly as VARIANT
-- here and populated with PARSE_JSON in post_deploy.sql.
-- SPLIT is 'DEV' (tune on these) or 'HOLDOUT' (only used to decide promotion);
-- assigned in post_deploy.sql so EVALS_TABLE.csv stays unchanged.
DEFINE TABLE {{db}}.DATA.EVALS_TABLE (
    INPUT_QUERY TEXT,
    GROUND_TRUTH_DATA VARIANT,
    SPLIT TEXT
);

-- Per-split sources for SYSTEM$CREATE_EVALUATION_DATASET.
DEFINE TABLE {{db}}.DATA.EVALS_TABLE_DEV (
    INPUT_QUERY TEXT,
    GROUND_TRUTH_DATA VARIANT
);

DEFINE TABLE {{db}}.DATA.EVALS_TABLE_HOLDOUT (
    INPUT_QUERY TEXT,
    GROUND_TRUTH_DATA VARIANT
);
