# Eval Based Agentic Optimization HOL  
Hands on Lab materials for building, evaluating and deploying AI Agents on Snowflake CoWork

> A self-paced version of this lab is available as a Snowflake Guide: [Build, Evaluate and Deploy AI Agents with Snowflake CoWork](https://www.snowflake.com/en/developers/guides/build-evaluate-and-deploy-ai-agents-with-snowflake-cowork/) (link goes live once the guide is published).

# Instructions

## 1. Setup (Snowsight, about 15 minutes)

Everything runs in Snowsight as **ACCOUNTADMIN**. The lab is a [DCM project](https://docs.snowflake.com/en/user-guide/dcm-projects/dcm-projects-overview) in [`dcm_project/`](dcm_project/).

1. **Prepare the account.** In Snowsight, open a new SQL file, paste in [`dcm_project/pre_deploy.sql`](dcm_project/pre_deploy.sql), and run all.
   > This turns on Cortex web search for the whole account (needed by the agent's web search tool). Review it with your admin first.
2. **Open the lab in a Workspace.** Go to **Projects > Workspaces**, then **Create Workspace > From Git repository**:
   - Repository URL: `https://github.com/Snowflake-Labs/build_deploy_ai_agents_snowflake_cowork_vhol.git`
   - API integration: `GIT_API_INTEGRATION_AI_AGENT_HOL`
   - Select **Public repository**, then **Create**.
3. **Deploy the DCM project.** In the workspace, select the `dcm_project` project, run **Plan**, review the changes, then **Deploy**.
4. **Load data, create the agent and start the baseline eval.** Open `dcm_project/post_deploy.sql` and run all.

You now have the data, a semantic view, a Cortex Search service, a report skill, the `MARKETING_AGENT` (`VERSION$1`), and a baseline evaluation run `MARKETING_AGENT_V1_DEV_R01`, which takes a few minutes to finish.

## 2. Eval Investigation

In Snowsight, navigate to your newly created Agent and click on the Evaluations tab. Check out your global metric scores and get a sense of where your baseline agent is. Look into individual records to understand how the agent performed across a variety of metrics for given queries. 

Navigate to **AI & ML > Agents > MARKETING_AGENT > Evaluations**.


<img width="1710" height="355" alt="image" src="https://github.com/user-attachments/assets/9fc1ab7f-f8ca-4ded-b062-858f6438375e" /> <br><br>
You should see your baseline evaluation run completed here (note your scores may vary!)

<img width="1710" height="879" alt="image" src="https://github.com/user-attachments/assets/01051989-7a79-4bd4-9839-05bd1395a337" />  <br><br>

Clicking into the eval run - we can see individual and aggregate scores for all records in our evalset. You can also click View Details on the top right corner this page to see run status, LLM judge model versions, custom metric prompts etc.

<img width="1710" height="879" alt="image" src="https://github.com/user-attachments/assets/1317c41a-e612-4f01-a439-1b7d0ee726a0" /> <br><br>

Clicking into a single record shows us the trace for that request and the metric scores. We can drill into each metric to see not only the score but the **criteria** the metric used to generate the score and the **reason** that score was given. This qualitative info combined with the quantitative scores gives agent developers, and importantly CoCo, very good feedback to understand the root cause of low eval scores.


## 3. Agent Optimization

Time to improve your agent with CoCo in Snowsight. Follow [coco_prompts.md](./coco_prompts.md): three short prompts.

The 15 eval questions are split into **10 development** questions (used to find and fix problems) and **5 held-out** questions (used only at the end to check that the fix generalizes). Promote the new version only if the held-out results support it.

> [!NOTE]
> 15 questions is a teaching-sized eval set, chosen to keep runtime and cost low. With 5 held-out questions, one question changing moves the score by 20 points, so treat results as a signal, not proof. Production evaluations need many more questions.

## 4. Test Your Agent in Snowflake CoWork

Now that your agent is optimized, try it the way your business users will - in Snowflake CoWork.

1. Make sure your user's default role is `AI_AGENT_HOL_ROLE` (CoWork uses your default role, and this role owns the agent and its tools).
2. Open Snowflake CoWork and select **MARKETING_AGENT** from the agent picker.
3. Ask a few questions that exercise different tools, for example:
    - "Which channels yield the highest click-through rates?" (Cortex Analyst)
    - "What was customer feedback around our back to school campaign?" (Cortex Search)
    - "Generate a report for the holiday gift guide campaign" (campaign report skill + code execution)
    - "Based on Pew Research Center's Americans' Social Media Use 2025 report, which platforms reach the most U.S. adults, and how do our social campaigns compare?" (web search + Cortex Analyst)

### Try Artifacts

When a response includes a chart or table worth keeping, select **Save** to turn it into an artifact. Artifacts are live references: they keep the underlying query and visualization, refresh against current data, and can be shared with teammates (who see results filtered by their own data permissions).

- Ask: "Show me total revenue and average ROI by campaign type as a bar chart" and save the chart.
- Open the artifacts hub to find it under **Saved**, then open it and ask a follow-up question.
- Optionally, share the conversation with a teammate via a link.

See [Artifacts in Snowflake CoWork](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/artifacts).

### Try Automations

Automations turn a question into a recurring report delivered to your email, re-run against the latest data each time.

- Ask: "Give me a weekly summary of our top 5 campaigns by ROI with key metrics", then reply "Send me this report every Monday at 9 AM".
- Or create one manually from the **Automations** tab with a name, instructions, and frequency.
- Review the automation in the Automations tab and cancel it when you're done with the lab (automations run on your compute).

See [Automations in Snowflake CoWork](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/automations).

## 5. Optional Stretch Goals

If you have time left, keep improving your agent; see the **Your turn** section of [coco_prompts.md](./coco_prompts.md). Commit each change as a new agent version and evaluate it on the development questions.

A few ideas of things to try
- An updated Semantic Model
- A new orchestration model
- Enriched tool descriptions

## License

Copyright 2026 Snowflake Inc.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

The sample data in `data/` is synthetic and was created for this lab.
