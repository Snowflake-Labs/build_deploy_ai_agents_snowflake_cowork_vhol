-- Lab role and grants.
-- DCM-managed objects are owned by the project owner (ACCOUNTADMIN); the lab role
-- gets read access to them plus CREATE privileges for what it builds itself
-- (search service, agent, git repo, datasets, eval tasks) in post_deploy.sql.

DEFINE ROLE {{role}}
    COMMENT = 'Lab role for the AI agent HOL';

-- The role is granted to whoever runs post_deploy.sql (CURRENT_USER), so no user list here.

GRANT USAGE ON WAREHOUSE {{wh}} TO ROLE {{role}};
GRANT USAGE ON DATABASE {{db}} TO ROLE {{role}};

{% for schema in ['DATA', 'ANALYTICS', 'AGENTS'] %}
GRANT USAGE ON SCHEMA {{db}}.{{schema}} TO ROLE {{role}};
{% endfor %}

-- DATA: read tables, use file format, create git repo / tables
GRANT SELECT ON TABLE {{db}}.DATA.CAMPAIGNS TO ROLE {{role}};
GRANT SELECT ON TABLE {{db}}.DATA.CAMPAIGN_PERFORMANCE TO ROLE {{role}};
GRANT SELECT ON TABLE {{db}}.DATA.CAMPAIGN_CONTENT TO ROLE {{role}};
GRANT SELECT ON TABLE {{db}}.DATA.CAMPAIGN_FEEDBACK TO ROLE {{role}};
GRANT SELECT ON TABLE {{db}}.DATA.EVALS_TABLE TO ROLE {{role}};
GRANT USAGE ON FILE FORMAT {{db}}.DATA.AGENT_EVAL_QUICKSTART_CSV_FORMAT TO ROLE {{role}};
GRANT CREATE TABLE, CREATE GIT REPOSITORY ON SCHEMA {{db}}.DATA TO ROLE {{role}};
GRANT USAGE ON INTEGRATION GIT_API_INTEGRATION_AI_AGENT_HOL TO ROLE {{role}};

-- ANALYTICS: semantic view + search service
GRANT SELECT ON SEMANTIC VIEW {{db}}.ANALYTICS.MARKETING_PERFORMANCE_ANALYST TO ROLE {{role}};
GRANT CREATE SEMANTIC VIEW, CREATE CORTEX SEARCH SERVICE ON SCHEMA {{db}}.ANALYTICS TO ROLE {{role}};

-- AGENTS: agent, skills, evals
GRANT READ, WRITE ON STAGE {{db}}.AGENTS.AGENT_SKILLS TO ROLE {{role}};
GRANT READ, WRITE ON STAGE {{db}}.AGENTS.EVAL_CONFIG_STAGE TO ROLE {{role}};
GRANT CREATE AGENT, CREATE PROCEDURE, CREATE TASK, CREATE STAGE, CREATE FILE FORMAT, CREATE DATASET
    ON SCHEMA {{db}}.AGENTS TO ROLE {{role}};

-- Account-level privileges
GRANT EXECUTE TASK ON ACCOUNT TO ROLE {{role}};
GRANT CREATE API INTEGRATION ON ACCOUNT TO ROLE {{role}};
