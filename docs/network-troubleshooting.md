<!-- SPDX-License-Identifier: MIT -->

# Network Troubleshooting Guide

This guide covers how to use Azure Network Watcher VNet flow logs and diagnostic
tools to troubleshoot connectivity issues in the healthcare referral routing
pipeline — specifically APIM ↔ Logic App communication over private endpoints.

## Architecture Overview

```
Internet → APIM (snet-apim, 10.0.1.0/24)
               ↓ VNet integration
           Private Endpoint (snet-private-endpoints, 10.0.2.0/24)
               ↓
           Logic App Standard (snet-logic-apps, 10.0.3.0/24)
               ↓ VNet integration
           Service Bus PE (snet-private-endpoints, 10.0.2.0/24)
```

All inter-service traffic stays within the VNet. Two NSGs control access:

| NSG | Subnets | Rules |
|-----|---------|-------|
| `nsg-apim` | snet-apim | Allows HTTPS (443), APIM Management (3443), Load Balancer (6390) |
| `nsg-pe` | snet-private-endpoints, snet-logic-apps, snet-jumpbox | Allows VNet-to-VNet only; denies all other inbound |

## VNet Flow Logs

VNet flow logs capture all traffic across every subnet in a single configuration,
replacing the deprecated NSG flow logs (blocked for new creation since June 2025).

### What's Deployed

| Resource | Value |
|----------|-------|
| Flow log name | `{baseName}-flowlog-vnet` |
| Target | VNet (`{baseName}-vnet`) |
| Storage account | `{baseName}flow` (dedicated, Standard_LRS) |
| Log format | JSON v2 |
| Retention | 30 days |
| Traffic Analytics | Enabled (10-min interval) |
| Log Analytics workspace | `{baseName}-law` |

### Flow Log Configuration

![Flow log settings showing VNet target, storage account, and 30-day retention](flowlogs-config.png)

*The flow log settings page shows the VNet resource, dedicated storage account,
and retention period.*

### Viewing Flow Logs in the Portal

1. Navigate to **Network Watcher** in the Azure portal
2. Under **Monitoring**, select **Traffic Analytics**
3. Set the **FlowLog Type** dropdown to **VNET** (not NSG)
4. Select your Log Analytics workspace
5. Data appears after 20–30 minutes from when flow logs were enabled

![Traffic Analytics page — data populates after 20-30 minutes](flowlogs-traffic-analytics.png)

> **Note:** Traffic Analytics requires 20–30 minutes of data collection before
> results appear. If you see "no data," wait and refresh.

## Troubleshooting Common Issues

### 1. APIM Cannot Reach Logic App (HTTP 500 / timeout)

**Symptoms:** APIM returns 500 or gateway timeout when calling the Logic App.

**Diagnosis steps:**

1. **Check NSG rules** — Verify `nsg-pe` allows VNet-to-VNet inbound traffic:

   ```powershell
   az network nsg rule list \
     --nsg-name "{baseName}-nsg-pe" \
     --resource-group "{resourceGroup}" \
     --query "[].{name:name, access:access, direction:direction, priority:priority, source:sourceAddressPrefix, dest:destinationAddressPrefix}" \
     -o table
   ```

2. **IP Flow Verify** — Test whether a specific packet would be allowed or denied:

   ![IP Flow Verify — test if traffic between subnets is allowed by NSG rules](flowlogs-ip-flow-verify.png)

   - **Virtual machine:** Select the jumpbox VM (or any VM in the VNet)
   - **Protocol:** TCP
   - **Direction:** Outbound
   - **Local IP:** Source subnet IP (e.g., `10.0.1.x` for APIM)
   - **Remote IP:** Destination PE IP (e.g., `10.0.2.x`)
   - **Remote port:** 443

   Or via CLI:

   ```powershell
   az network watcher test-ip-flow \
     --direction Outbound \
     --protocol TCP \
     --local "10.0.1.4:*" \
     --remote "10.0.2.5:443" \
     --vm "{baseName}-jbox" \
     --resource-group "{resourceGroup}"
   ```

3. **Query flow logs in Log Analytics:**

   ```kusto
   AzureNetworkAnalytics_CL
   | where FlowType_s == "IntraVNet"
   | where SrcIP_s startswith "10.0.1"     // APIM subnet
   | where DestIP_s startswith "10.0.2"    // PE subnet
   | where DestPort_d == 443
   | project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d,
             FlowStatus_s, NSGRule_s, FlowDirection_s
   | order by TimeGenerated desc
   | take 50
   ```

4. **Check private endpoint DNS resolution:**

   ```powershell
   # From the jumpbox, verify DNS resolves to private IP
   nslookup {logicAppName}.azurewebsites.net
   # Should resolve to 10.0.2.x (private endpoint IP), NOT a public IP
   ```

### 2. Logic App Cannot Reach Service Bus (Send_to_Queue Fails)

**Symptoms:** Logic App workflow action `Send_to_Incoming_Queue` returns
`NotFound` or `Unauthorized`.

**Diagnosis steps:**

1. **Check Service Bus network rules:**

   ```powershell
   az servicebus namespace show \
     --name "{baseName}-sbns" \
     --resource-group "{resourceGroup}" \
     --query "{publicAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}"
   ```

   - `publicNetworkAccess` should be `Disabled` (traffic goes via PE)
   - `defaultAction` should be `Deny`

2. **Verify private endpoint health:**

   ```powershell
   az network private-endpoint show \
     --name "{baseName}-pe-servicebus" \
     --resource-group "{resourceGroup}" \
     --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState"
   ```

   Status should be `Approved`.

3. **Query denied flows to Service Bus PE:**

   ```kusto
   AzureNetworkAnalytics_CL
   | where DestIP_s == "10.0.2.4"          // Service Bus PE IP
   | where FlowStatus_s == "D"             // Denied
   | project TimeGenerated, SrcIP_s, DestPort_d, NSGRule_s
   | order by TimeGenerated desc
   ```

4. **Check API connection status** (Consumption Logic Apps only):

   ```powershell
   az rest --method GET \
     --url "/subscriptions/{subId}/resourceGroups/{rg}/providers/Microsoft.Web/connections/servicebus-connection?api-version=2018-07-01-preview" \
     --query "{status:properties.statuses[0].status, error:properties.statuses[0].error}"
   ```

### 3. Blocked Traffic Investigation

**Symptoms:** Expected traffic is being dropped silently.

**Diagnosis with flow logs:**

```kusto
// Find all denied flows in the last hour
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where FlowStatus_s == "D"
| summarize Count=count() by SrcIP_s, DestIP_s, DestPort_d, NSGRule_s
| order by Count desc
```

```kusto
// Find flows blocked by a specific NSG rule
AzureNetworkAnalytics_CL
| where NSGRule_s contains "Deny-All-Inbound"
| project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d
| order by TimeGenerated desc
| take 20
```

### 4. Effective Security Rules

View the combined effect of all NSG rules on a network interface:

```powershell
az network nic list-effective-nsg \
  --name "{nicName}" \
  --resource-group "{resourceGroup}" \
  --query "value[].effectiveSecurityRules[].{name:name, access:access, direction:direction, priority:priority, srcPrefix:sourceAddressPrefix, dstPrefix:destinationAddressPrefix, dstPort:destinationPortRange}" \
  -o table
```

Or use the **Effective security rules** tool in Network Watcher (under
*Network diagnostic tools*).

## Network Watcher Tools Reference

![Network Watcher overview — diagnostic tools available per region](flowlogs-nw-overview.png)

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **Traffic Analytics** | Visualize flow patterns, top talkers, denied traffic | Ongoing monitoring, capacity planning |
| **IP Flow Verify** | Test if a packet is allowed/denied by NSG rules | Quick NSG rule validation |
| **NSG Diagnostics** | Detailed NSG rule evaluation for a specific flow | Deep-dive into why traffic is blocked |
| **Connection Troubleshoot** | End-to-end connectivity test between two endpoints | Verify APIM → Logic App path works |
| **Next Hop** | Determine routing path for traffic | Diagnose routing issues (UDRs) |
| **Effective Security Rules** | View merged NSG rules on a NIC | Understand combined rule effects |
| **Packet Capture** | Capture network packets on a VM NIC | Deep protocol-level debugging |

## Subnet & IP Reference

| Subnet | CIDR | Key Resources | Private IPs |
|--------|------|---------------|-------------|
| snet-apim | 10.0.1.0/24 | API Management (StandardV2) | APIM VIP |
| snet-private-endpoints | 10.0.2.0/24 | Service Bus PE, Key Vault PE, Grafana PE, Logic App PE | 10.0.2.4+ |
| snet-logic-apps | 10.0.3.0/24 | Logic App Standard (VNet integrated) | Dynamic |
| snet-jumpbox | 10.0.4.0/24 | Jumpbox VM (Bastion access) | 10.0.4.4 |

## Bicep Modules

Flow logs are defined in two modules:

- **`modules/flow-logs.bicep`** — Creates the storage account and orchestrates
  the cross-resource-group deployment
- **`modules/flow-logs-nw.bicep`** — Deploys the VNet flow log resource into
  `NetworkWatcherRG` (where Network Watcher lives)

To deploy standalone:

```powershell
az deployment group create `
  --resource-group "{resourceGroup}" `
  --template-file modules/flow-logs.bicep `
  --parameters location=eastus2 baseName="{baseName}" `
               vnetId="{vnetResourceId}" `
               workspaceId="{lawResourceId}" `
               tags='{"project":"healthcare-referral-demo"}'
```
