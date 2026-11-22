-- ====================================================================
-- pre_deploy.sql - run BEFORE `snow dcm plan` / `snow dcm deploy`:
--   snow sql -c target_dev -f pre_deploy.sql
-- Creates the container that hosts the DCM project object (a project cannot
-- define its own parent database/schema) and registers the project.
-- ====================================================================

USE ROLE ACCOUNTADMIN;

-- !! ACCOUNT-LEVEL PARAMETER CHANGE - REVIEW BEFORE RUNNING !!
-- Required by the web_search tool on MARKETING_AGENT (created in post_deploy.sql).
-- Applies to the ENTIRE ACCOUNT. To skip, comment out and remove the web_search
-- tool from the agent spec. Revert with: ALTER ACCOUNT UNSET ENABLE_CORTEX_WEBSEARCH;
ALTER ACCOUNT SET ENABLE_CORTEX_WEBSEARCH = TRUE;

-- Home for the DCM project object
CREATE DATABASE IF NOT EXISTS AI_AGENT_HOL_ADMIN
    COMMENT = 'Hosts the AI_AGENT_HOL DCM project';
CREATE SCHEMA IF NOT EXISTS AI_AGENT_HOL_ADMIN.DCM;

-- Register the project (equivalent: snow dcm create AI_AGENT_HOL_ADMIN.DCM.AI_AGENT_HOL -c target_dev)
CREATE DCM PROJECT IF NOT EXISTS AI_AGENT_HOL_ADMIN.DCM.AI_AGENT_HOL;
