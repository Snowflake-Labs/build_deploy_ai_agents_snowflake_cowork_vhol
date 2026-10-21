# Eval Based Agentic Optimization HOL  
Hands on Lab materials for building, evaluating and deploying AI Agents on Snowflake CoWork

# Instructions

## 1. Setup 

Run the [SETUP.sql](SETUP.sql) file to provision a new database with data, a semantic view, a Cortex Search service and a campaign report agent skill before wrapping these services (plus code execution and web search) into a baseline agent and running your first evaluation.

## 2. Eval Investigation

In Snowsight, navigate to your newly created Agent and click on the Evaluations tab. Check out your global metric scores and get a sense of where your baseline agent is. Look into individual records to understand how the agent performed across a variety of metrics for given queries. 

Start with the link generated at the end of your setup SQL - or navigate to Agents -> Marketing_Agent -> Evaluations


<img width="1710" height="355" alt="image" src="https://github.com/user-attachments/assets/9fc1ab7f-f8ca-4ded-b062-858f6438375e" /> <br><br>
You should see your baseline evaluation run completed here (note your scores may vary!)

<img width="1710" height="879" alt="image" src="https://github.com/user-attachments/assets/01051989-7a79-4bd4-9839-05bd1395a337" />  <br><br>

Clicking into the eval run - we can see individual and aggregate scores for all records in our evalset. You can also click View Details on the top right corner this page to see run status, LLM judge model versions, custom metric prompts etc.

<img width="1710" height="879" alt="image" src="https://github.com/user-attachments/assets/1317c41a-e612-4f01-a439-1b7d0ee726a0" /> <br><br>

Clicking into a single record shows us the trace for that request and the metric scores. We can drill into each metric to see not only the score but the **criteria** the metric used to generate the score and the **reason** that score was given. This qualitative info combined with the quantitative scores gives agent developers, and importantly CoCo, very good feedback to understand the root cause of low eval scores.


## 3. Agent Optimization

Time to improve your agent using CoCo! You have two options depending on your environment. Both options use the same prompts from [coco_prompts.txt](./coco_prompts.txt) to analyze the evaluation results and drive improvements.

---

### Which option should I choose?

| | Option 1: CoCo Snowsight | Option 2: CoCo CLI |
|---|---|---|
| **Where it runs** | In your browser via Snowsight | Locally on your machine (or in GitHub Codespaces) |
| **Setup friction** | Low — already available in Snowsight | Moderate — requires CLI install and connection config |
| **Control** | Uses a Snowflake workspace for file context; same CoCo capabilities via the Snowsight chat panel | Full local filesystem, can read/write agent YAML files directly, supports all `cortex agent-studio` subcommands |
| **Best for** | Attendees whose org restricts local tooling or who want the quickest path | Attendees whose org has approved the CoCo CLI / Codespaces |

Both options produce the same result: improved agent instructions saved as a new committed version, and a re-evaluation run to measure the improvement.

> [!WARNING]
> **Choose one option and stick with it.** Do not switch between CLI and Snowsight mid-lab.

---

### Option 1 (recommended): CoCo Snowsight (browser-based)

No local install required. Follow the full setup guide: [coco_snowsight_setup.md](./coco_snowsight_setup.md)

### Option 2: CoCo CLI (via GitHub Codespaces or local)

Follow the full setup guide: [coco_cli_setup.md](./coco_cli_setup.md)

---

## 4. Test Your Agent in Snowflake CoWork

Now that your agent is optimized, try it the way your business users will - in Snowflake CoWork.

1. Make sure your user's default role is `COWORK_AI_HOL_ROLE` (CoWork uses your default role, and this role owns the agent and its tools).
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

You should have seen a decent improvement in your evaluation metrics going from your baseline to your optimized agent. If you have time left, see how far you can take your agent! This is your turn to use your AI and Snowflake knowledge to apply new methods to the agent and push agent quality even higher. Remember to commit each change as a new agent version and re-run your evaluation against it.

A few ideas of things to try
- An updated Semantic Model
- A new orchestration model
- Enriched tool descriptions
