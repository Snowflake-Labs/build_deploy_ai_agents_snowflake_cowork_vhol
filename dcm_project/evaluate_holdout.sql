-- ====================================================================
-- Held-out evaluation (CoCo Prompt 3). Run ONLY after the candidate version is frozen,
-- i.e. after Prompt 2 (MARKETING_AGENT_V2_DEV_R01) has completed and you are done
-- changing the agent, before you change the agent again.
--
-- Dataset usage:
--   | Step                      | Version   | Dataset | Run name                       |
--   |---------------------------|-----------|---------|--------------------------------|
--   | Deploy (post_deploy.sql)  | VERSION$1 | DEV     | MARKETING_AGENT_V1_DEV_R01     |
--   | Prompt 1: diagnose + edit | -         | DEV     | (tune on DEV results only)     |
--   | Prompt 2: candidate       | VERSION$2 | DEV     | MARKETING_AGENT_V2_DEV_R01     |
--   | Prompt 3: this script     | VERSION$1 | HOLDOUT | MARKETING_AGENT_V1_HOLDOUT_R01 |
--   | Prompt 3: this script     | VERSION$2 | HOLDOUT | MARKETING_AGENT_V2_HOLDOUT_R01 |
--
-- Promote VERSION$2 only if the HOLDOUT rows support it. If you tune again after
-- looking at these results, HOLDOUT is no longer unseen.
-- If your candidate is not VERSION$2, edit agent_version in
-- files/evals/marketing_campaign_eval_config_holdout_candidate.yaml and re-PUT it.
-- ====================================================================
USE ROLE AI_AGENT_HOL_ROLE;
USE WAREHOUSE AI_AGENT_HOL_WH;
USE SCHEMA AI_AGENT_HOL_DB.AGENTS;

CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'MARKETING_AGENT_V1_HOLDOUT_R01'),
  '@AI_AGENT_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config_holdout_baseline.yaml'
);

CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'MARKETING_AGENT_V2_HOLDOUT_R01'),
  '@AI_AGENT_HOL_DB.AGENTS.EVAL_CONFIG_STAGE/marketing_campaign_eval_config_holdout_candidate.yaml'
);
