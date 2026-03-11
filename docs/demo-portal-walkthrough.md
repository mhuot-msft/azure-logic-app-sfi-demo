# Live Demo: Create a Logic App in the Azure Portal

This walkthrough guides the presenter through creating an **Urgent Referral Alert** Logic App live in the Azure Portal during the demo. It takes ~3 minutes and shows how Logic Apps can be built visually - just like Power Automate - then explains how the same thing can be expressed as infrastructure-as-code.

> **Pre-requisite:** The main pipeline must already be deployed via `./deploy.ps1`.

---

## Step 1: Open Logic Apps in the Portal

Navigate to **Logic Apps** in the Azure Portal, or use the direct URL:

```
https://portal.azure.com/#browse/Microsoft.Logic%2Fworkflows
```

You should see the two existing Logic Apps (intake and router) that were deployed via Bicep.

![Logic Apps list](screenshots/01-logic-apps-list.png)

**Talking point:** *"Here are the two Logic Apps we deployed with infrastructure-as-code. Now let's add a third one - live in the portal - to show how easy it is to extend this pipeline."*

---

## Step 2: Create a New Logic App

1. Click **+ Create** in the toolbar
2. Select **Consumption - Multi-tenant** (same tier as our existing Logic Apps)

![Select hosting plan](screenshots/02-create-logic-app-type.png)

**Talking point:** *"Consumption is pay-per-execution - perfect for event-driven workflows. Standard gives you dedicated hosting with VNET integration for enterprise scenarios."*

3. Click **Select**

---

## Step 3: Fill in the Basics

| Field | Value |
|-------|-------|
| **Resource Group** | `rg-healthcare-referral-demo` (select existing) |
| **Logic App name** | `urgent-referral-alert` |
| **Region** | `East US 2` (match existing resources) |
| **Enable log analytics** | No (keep it quick for demo) |
| **Workflow Type** | Stateful |

![Filled basics form](screenshots/04-create-basics-filled.png)

**Talking point:** *"Notice the Conversational Agents and Autonomous Agents options - these are new Preview features that let Logic Apps use AI agents. We'll stick with Stateful for this demo."*

4. Click **Review + create**, then **Create**
5. Wait for deployment (~30 seconds)

![Deployment complete](screenshots/06-deployment-complete.png)

6. Click **Go to resource**

---

## Step 4: Open the Designer

1. Click **Edit** on the Logic App overview page to open the visual designer

![Empty designer](screenshots/08-designer-empty.png)

**Talking point:** *"This is the same drag-and-drop designer experience as Power Automate. The difference is that this runs as an Azure resource with managed identity, RBAC, and full DevOps support."*

---

## Step 5: Add the Service Bus Trigger

1. Click **Add a trigger**
2. Search for **Service Bus**

![Service Bus triggers](screenshots/10-trigger-service-bus-search.png)

3. Select **When a message is received in a queue (auto-complete)**

The designer will show the connection panel. It should find the existing **Service Bus (Managed Identity)** connection from our deployment.

![Connection selection](screenshots/12-change-connection.png)

4. Select the existing connection and click through

5. In the **Queue name** dropdown, select **`urgent-referrals`**

**Talking point:** *"This Logic App is now listening to the same urgent-referrals queue that our Router Logic App writes to. No code changes needed to the existing pipeline - we're just adding a new consumer."*

---

## Step 6: Add a Compose Action (Parse the Message)

1. Click the **+** button below the trigger, then **Add an action**
2. Search for **Compose** (under Data Operations)
3. In the **Inputs** field, click in the text box and select **Dynamic content** > **Content** (from the trigger)

This extracts the message body from the Service Bus message.

**Talking point:** *"In production you'd add Parse JSON here to extract individual fields, then send an email or Teams notification. For the demo, Compose lets us see the message content in the run history."*

---

## Step 7: Save and Test

1. Click **Save** in the toolbar
2. Go back to your terminal and send an urgent referral:

```powershell
$body = @{
    patientId = "PT-2025-99999"
    patientName = "Demo Patient"
    referralType = "Cardiology"
    priority = "urgent"
    diagnosis = @{ code = "I25.10"; description = "Atherosclerotic heart disease" }
    referringProvider = "Dr. Demo, MD"
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri $endpoint -Method Post -Headers @{
    "Content-Type" = "application/json"
    "Ocp-Apim-Subscription-Key" = $subKey
} -Body $body
```

3. Return to the portal and click **Overview** > **Runs history** to see the run
4. Click the run to expand each step and show the message content flowing through

**Talking point:** *"The referral went through our Intake Logic App, got enriched with a correlationId and timestamp, was routed to the urgent-referrals queue by the Router, and now this new Logic App picked it up. Three Logic Apps, all connected through Service Bus, deployed in minutes."*

---

## Step 8: Bridge to IaC (Key Demo Moment)

1. In the designer, click **Code view** in the toolbar
2. Show the JSON workflow definition

**Talking point:** *"Everything we just built in the portal is stored as this JSON definition. This is exactly what goes inside a Bicep template. So the workflow is: prototype in the portal, export to code, check into source control. Or do what we did - write the Bicep from the start and deploy it through a CI/CD pipeline."*

3. Optionally show the **Export template** option from the Logic App resource blade

---

## Cleanup

After the demo, delete the Logic App created in the portal:

```powershell
az logic workflow delete --resource-group rg-healthcare-referral-demo --name urgent-referral-alert --yes
```

Or leave it - it will be deleted when the resource group is torn down.

---

## Quick Reference

| Item | Value |
|------|-------|
| Logic App name | `urgent-referral-alert` |
| Resource Group | `rg-healthcare-referral-demo` |
| Region | East US 2 |
| Trigger | Service Bus - When a message is received in a queue (auto-complete) |
| Queue | `urgent-referrals` |
| Connection | Existing Service Bus (Managed Identity) |
| Action | Compose (message content) |
