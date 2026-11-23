-- Semantic view for Cortex Analyst

DEFINE SEMANTIC VIEW {{db}}.ANALYTICS.MARKETING_PERFORMANCE_ANALYST
  TABLES (
    campaigns AS {{db}}.DATA.CAMPAIGNS PRIMARY KEY (campaign_id),
    performance AS {{db}}.DATA.CAMPAIGN_PERFORMANCE PRIMARY KEY (performance_id)
  )
  RELATIONSHIPS (
    performance_to_campaigns AS performance (campaign_id) REFERENCES campaigns (campaign_id)
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
