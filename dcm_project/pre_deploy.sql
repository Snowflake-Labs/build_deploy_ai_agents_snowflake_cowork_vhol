-- ====================================================================
-- pre_deploy.sql - run FIRST, as ACCOUNTADMIN, in a Snowsight SQL worksheet.
-- 1. Enables Cortex web search (used by the agent's web_search tool).
-- 2. Creates the Git API integration so you can create a Workspace from the lab repo.
-- 3. Creates the container for the DCM project object and registers the project
--    (a project cannot define its own parent database/schema).
-- ====================================================================

USE ROLE ACCOUNTADMIN;

-- !! ACCOUNT-LEVEL PARAMETER CHANGE - REVIEW BEFORE RUNNING !!
-- Applies to the ENTIRE ACCOUNT. To skip, comment out and remove the web_search
-- tool from the agent spec. Revert with: ALTER ACCOUNT UNSET ENABLE_CORTEX_WEBSEARCH;
ALTER ACCOUNT SET ENABLE_CORTEX_WEBSEARCH = TRUE;

-- Needed before the DCM deploy, to create the Workspace from Git.
-- Properties match the DEFINE in sources/definitions/infrastructure.sql, so the deploy adopts it unchanged.
CREATE API INTEGRATION IF NOT EXISTS GIT_API_INTEGRATION_AI_AGENT_HOL
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs/')
    ENABLED = TRUE
    COMMENT = 'Public GitHub access for the AI agent HOL repo';

-- Home for the DCM project object
CREATE DATABASE IF NOT EXISTS AI_AGENT_HOL_ADMIN
    COMMENT = 'Hosts the AI_AGENT_HOL DCM project';
CREATE SCHEMA IF NOT EXISTS AI_AGENT_HOL_ADMIN.DCM;

-- Register the project (equivalent: snow dcm create AI_AGENT_HOL_ADMIN.DCM.AI_AGENT_HOL)
CREATE DCM PROJECT IF NOT EXISTS AI_AGENT_HOL_ADMIN.DCM.AI_AGENT_HOL;
