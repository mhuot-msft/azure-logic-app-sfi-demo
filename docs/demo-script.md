# Demo Script: Azure Logic Apps Healthcare Referral Routing

**Duration**: 15 minutes
**Audience**: Healthcare IT leadership, architects, compliance officers
**Prerequisites**: Environment deployed via `deploy.ps1`, browser open to Azure Portal

---

## Pre-Demo Checklist

- [ ] Run `./demo-helper.ps1 -ResourceGroupName rg-healthcare-referral-demo` to verify all resources are healthy
- [ ] Have terminal open with `test-referral.ps1` command ready to paste
- [ ] Have Azure Portal open and logged in
- [ ] Have this script accessible on a second screen or printed
- [ ] Confirm APIM endpoint and subscription key are saved (from deploy output)
- [ ] Clear any previous Logic App run histories if re-running the demo

---

## Section 1: Problem Statement (0:00 - 2:00)

### What to say

> "Every day, your organization processes thousands of patient referrals. A cardiologist referral marked urgent can't wait in the same queue as a routine physical therapy follow-up. When urgent referrals get buried in a general queue, patients wait longer for critical care — and that's a compliance risk.
>
> Today I'm going to show you how Azure Logic Apps can automatically intake, validate, and route referrals by priority — with zero code, full HIPAA-aligned security controls, and a deployment that takes five minutes."

### Key points to emphasize

- Manual triage is error-prone and doesn't scale
- Missed urgent referrals = delayed care = liability
- This solution is fully automated, auditable, and runs at pennies per referral

---

## Section 2: Architecture Walkthrough (2:00 - 4:00)

### What to show

Open the architecture diagram (`docs/architecture.excalidraw` in Excalidraw, or show the Mermaid diagram from the README).

### What to say

> "Here's the end-to-end flow. A referral comes in as an API call — just like it would from your EHR system or a web portal.
>
> It hits **API Management** first — that's your front door. It handles authentication, rate limiting, and gives you a clean API contract.
>
> Behind that sits the **Intake Logic App**. It validates the referral against a schema — patient ID, diagnosis code, priority level — and enriches it with a correlation ID for tracking. Then it drops it on a **Service Bus queue**.
>
> A second **Router Logic App** picks up the message and checks the priority. Urgent and high-priority referrals go to one queue. Normal and low go to another. That's your triage — automated, consistent, instant.
>
> Underneath all of this: **Key Vault** for secrets management, **Managed Identity** so there are zero passwords in the code, and **Log Analytics** capturing every action for your compliance team."

### Key points to emphasize

- Two-stage pipeline pattern (intake vs. routing) for separation of concerns
- Managed Identity means zero credential management
- Every component logs to a centralized workspace

---

## Section 3: Show the Code (4:00 - 6:00)

### What to show

Open `main.bicep` in VS Code or a code viewer.

### What to say

> "The entire infrastructure is defined in Bicep — Azure's Infrastructure-as-Code language. This is the main orchestrator file. It calls nine modules in the right dependency order.
>
> *(Scroll through the module calls)*
>
> Each module is focused: one for Service Bus, one for Key Vault, one for each Logic App. The Logic Apps define their workflows right in the Bicep template — the trigger, the validation schema, the routing logic — it's all here, version-controlled, reviewable.
>
> *(Open `modules/logic-app-intake.bicep`, scroll to the schema section around line 40)*
>
> Here's the referral schema. Six required fields: patient ID, name, referral type, priority, diagnosis code, and referring provider. If any of these are missing, the Logic App rejects it immediately with a 400 error. No bad data gets into the pipeline.
>
> *(Scroll to the Process_Referral scope)*
>
> Notice the structure here — the valid path is wrapped in a **Scope** called Process_Referral. That's our try block. If anything inside it fails — the enrichment, the queue send — it falls through to Handle_Processing_Error, which returns a clean 500 error. This is the same try-catch pattern you'd use in application code, but declarative.
>
> Inside the scope, you can see two Compose actions that run **in parallel** — Enrich_Metadata generates the correlation ID and timestamp, while Assemble_Clinical_Data pulls the patient fields. They merge together before the queue send. In a real system with external lookups, this parallelism saves time.
>
> Also notice the **retry policy** on Send_to_Incoming_Queue — exponential backoff, three attempts, up to one hour. If Service Bus has a transient hiccup, the workflow retries automatically instead of failing.
>
> *(Open `modules/logic-app-router.bicep`, scroll to Check_Priority around line 60)*
>
> And here's the routing logic — a simple condition: if priority is urgent or high, route to the urgent queue. Everything else goes to standard. Same retry policies on both send actions. Clean and auditable."

### Key points to emphasize

- Everything is Infrastructure-as-Code — no Portal click-ops
- Schema validation catches bad data at the front door
- Scopes provide try-catch error handling in declarative workflows
- Parallel actions demonstrate concurrent execution
- Retry policies handle transient failures automatically
- Routing logic is transparent and version-controlled

---

## Section 4: Deployment (6:00 - 8:00)

### What to show

Azure Portal — Resource Group view showing all deployed resources.

### What to say

> "I deployed this environment earlier using a single PowerShell command. Let me show you what it created.
>
> *(Navigate to: Portal > Resource Groups > rg-healthcare-referral-demo)*
>
> You can see nine resources here: API Management, two Logic Apps, Service Bus with three queues, Key Vault, Log Analytics, and the API connection.
>
> *(Click into the Service Bus namespace, show the three queues)*
>
> Three queues: incoming referrals — that's the intake buffer. Urgent referrals and standard referrals — those are the routed outputs.
>
> The entire deployment takes about five to six minutes. One command, one parameter file, fully repeatable."

### Portal navigation

1. Portal Home > Resource Groups > `rg-healthcare-referral-demo`
2. Click the Service Bus namespace > Queues blade
3. Show the three queues: `incoming-referrals`, `urgent-referrals`, `standard-referrals`

### If asked about deployment time

> "API Management Consumption tier deploys in about two minutes. If we used the Developer tier, that alone would take 30-40 minutes. Consumption is the right choice for demos and low-volume workloads."

---

## Section 5: Live Test (8:00 - 11:00)

### What to do

Run the test script from terminal. This is the highlight of the demo — take your time here.

### What to say and do

> "Now let's see it work. I'm going to send three referrals through the system."

**Paste and run:**
```powershell
./test-referral.ps1 -ApiEndpoint "<YOUR_ENDPOINT>" -SubscriptionKey "<YOUR_KEY>"
```

**Test 1 fires — urgent cardiology:**

> "First referral: Sarah Mitchell, urgent cardiology. She has atherosclerotic heart disease — ICD code I25.10 — with exertional dyspnea. This needs to get to a cardiologist fast.
>
> *(Point to the 202 Accepted and correlation ID in the output)*
>
> Accepted. The system gave us back a correlation ID — that's our tracking number across the entire pipeline."

*(3-second pause — script handles this automatically)*

**Test 2 fires — normal PT:**

> "Second referral: David Chen, normal priority physical therapy for low back pain. Routine, not urgent.
>
> *(Point to the 202 Accepted)*
>
> Also accepted. But this one will go to a different queue."

*(3-second pause)*

**Test 3 fires — invalid payload:**

> "Third test: I'm intentionally sending bad data — missing required fields.
>
> *(Point to the 400 Bad Request)*
>
> Rejected. A 400 error. The schema validation caught it before it ever reached the queue. No garbage in the pipeline."

### Now show the Portal results

> "Let's go to the Portal and see what happened behind the scenes."

**Navigate to Intake Logic App:**

1. Portal > Resource Groups > `rg-healthcare-referral-demo`
2. Click the intake Logic App (`hlth-dev-*-intake`)
3. Click **Run history** in the left nav

> "Three runs. Two succeeded — those are our valid referrals. One failed — that's the validation rejection. Exactly what we expected."

*(Click on a succeeded run to show the workflow visualization)*

> "Here you can see each step: the HTTP trigger received the payload, the Compose action enriched it with a correlation ID and timestamp, and then it was sent to the incoming queue. Green checkmarks all the way."

**Navigate to Router Logic App:**

1. Back to resource group
2. Click the router Logic App (`hlth-dev-*-router`)
3. Click **Run history**

> "The router picked up both messages. Let's look at one."

*(Click on a run, show the If/Else branch)*

> "See the condition check? It evaluated the priority field, determined this was urgent, and routed it to the urgent-referrals queue. The other run took the else branch and went to standard."

**Navigate to Service Bus queues:**

1. Back to resource group
2. Click Service Bus namespace
3. Click **Queues**

> "And here's the final proof: urgent-referrals has one message, standard-referrals has one message. Sarah Mitchell went urgent, David Chen went standard. Automated triage in milliseconds."

---

## Section 6: Observability (11:00 - 13:00)

### What to show

Open the Grafana dashboard (URL from deploy output, or opened by `demo-helper.ps1`).

### What to say and do

> "Now let me show you the operational dashboard. This is Azure Managed Grafana — it's connected directly to our Log Analytics workspace and Azure Monitor metrics. The deployment created this dashboard automatically."

*(Navigate to the Healthcare Referral Routing dashboard)*

> "At the top, four summary panels: total referrals received, urgent count, standard count, and validation errors. Right now we can see the three referrals we just sent — one urgent, one standard, one rejected.
>
> *(Point to the time series panels)*
>
> These charts show intake and router Logic App runs over time — green bars for successes, red for failures. In production with hundreds of referrals per hour, you'd see the throughput pattern here instantly.
>
> *(Point to the queue message flow panel)*
>
> This tracks messages flowing through each Service Bus queue. You can see exactly when messages arrived in incoming, and when they were routed to urgent and standard.
>
> *(Point to the active messages bar gauge)*
>
> Active messages per queue — this is your backlog indicator. If urgent-referrals starts building up, someone needs to know. You could set a Grafana alert to fire when this exceeds a threshold.
>
> *(Point to the recent activity table)*
>
> And at the bottom, a live activity feed — every workflow run with its status and tracking ID. Your compliance team gets this view without writing a single query."

### Why Grafana instead of just KQL?

If asked:

> "Log Analytics is powerful, but it requires writing KQL queries. Grafana gives you a visual dashboard that updates in real time — much better for ops teams and executives who need a glance, not a query language. And because it's Azure Managed Grafana, there's nothing to install or maintain."

### Application Insights

If asked about deeper diagnostics:

> "We also deploy Application Insights, backed by the same Log Analytics workspace. Application Insights gives you richer diagnostics — dependency tracking, failure analysis, and performance profiling. For Logic Apps, it captures every workflow run with detailed timing and error data. In production, you'd use Application Insights for troubleshooting individual referrals and Grafana for the operational big picture."

### Fallback — if Grafana data is sparse

If Log Analytics hasn't ingested enough data yet:

> "Diagnostic data takes 5-10 minutes to appear on first run. Let me show you what this looks like with the raw KQL query in Log Analytics."

**Switch to Log Analytics:**
1. Back to resource group > Log Analytics workspace > Logs
2. Paste this query:
```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.LOGIC"
| where Category == "WorkflowRuntime"
| project TimeGenerated, resource_workflowName_s, status_s, correlation_clientTrackingId_s
| order by TimeGenerated desc
| take 20
```

> "This is the same data powering the Grafana dashboard — timestamped, with the workflow name, status, and correlation ID for end-to-end tracking."

---

## Section 7: Extensibility & Cost (13:00 - 15:00)

### What to say

> "What I showed you today is a starting point. Here's where you can take it:
>
> **Stateful workflows (Standard tier)** — Today's demo uses the Consumption tier, which runs stateless — each workflow executes and forgets. For long-running referral processes that need to wait for specialist responses or track multi-step approvals over days, the Standard tier offers stateful workflows that persist data across runs. Standard also gives you VNET integration, private endpoints, and local development in VS Code.
>
> **Teams or email alerts** — Add a Logic App action to send a Teams notification when an urgent referral is received. It's one extra step in the workflow.
>
> **FHIR integration** — The referral schema is already FHIR-like. You can swap the HTTP trigger for an Azure FHIR Server event, or add a step to write back to your EHR.
>
> **ML-based triage** — Replace the simple if/else with an Azure ML model that scores referral urgency based on clinical notes and diagnosis history.
>
> **Multi-region** — Service Bus supports geo-disaster recovery. You can replicate this across regions for high availability."

### Cost discussion

> "On cost: API Management Consumption tier bills per call — about three fifty per million. Logic Apps charge per action — fractions of a cent. Service Bus Standard is about ten dollars a month base.
>
> For a hospital processing a thousand referrals a day, you're looking at **under fifty dollars a month**. Compare that to the cost of a missed urgent referral."

### Cleanup

> "And when you're done, one command tears everything down:
>
> `az group delete --name rg-healthcare-referral-demo --yes --no-wait`
>
> Every resource, gone. No orphaned infrastructure, no surprise bills."

### Closing

> "To summarize: we took a real healthcare problem — referral triage — and solved it with a fully automated, HIPAA-aligned pipeline that deploys in five minutes, costs pennies to run, and gives your compliance team a complete audit trail. All Infrastructure-as-Code, all version-controlled, all repeatable."

---

## Q&A Prompts

If the audience is quiet, prompt with:

- "What does your current referral workflow look like today?"
- "How are you handling urgent vs. routine prioritization currently?"
- "What compliance requirements does your team need to satisfy for referral data?"
- "Are there other workflows beyond referrals that follow this same pattern — intake, validate, route?"

---

## Recovery Tips

| Issue | Recovery |
|-------|----------|
| **Test script returns 401** | Subscription key may be wrong. Re-run `demo-helper.ps1` to get the correct key. |
| **Test script returns 404** | APIM may still be deploying. Wait 1-2 minutes and retry. |
| **Logic App runs don't appear** | Runs take a few seconds to show. Refresh the Portal page. |
| **Router hasn't processed messages** | The router polls every 30 seconds. Wait up to a minute, then refresh. |
| **Log Analytics shows no data** | Ingestion takes 5-10 minutes on first run. Use Service Bus metrics as a fallback. |
| **APIM returns 429 (rate limited)** | Wait 60 seconds — the rate limit is 10 calls per minute. |
| **Portal is slow** | Use Portal keyboard shortcuts: `G + /` to search for resources. |
