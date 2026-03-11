# Licensed under the Apache License, Version 2.0
#
# demo-helper.ps1 — Pre-demo validation, Portal links, and cheat sheet
# Usage: ./demo-helper.ps1 [-ResourceGroupName <name>]

param(
    [string]$ResourceGroupName = "rg-healthcare-referral-demo"
)

$ErrorActionPreference = "Stop"

$totalChecks = 0
$passedChecks = 0
$hadIssue = $false
$showGrafanaExtensionHelp = $false

function Add-CheckResult {
    param(
        [bool]$Success
    )

    $script:totalChecks++
    if ($Success) {
        $script:passedChecks++
    } else {
        $script:hadIssue = $true
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Demo Helper — Pre-Flight Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── Verify Azure Login ──────────────────────────────────────────────

$accountRaw = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure. Run: az login"
    exit 1
}
$account = $accountRaw | ConvertFrom-Json
$subscriptionId = $account.id
Write-Host "Subscription: $($account.name)" -ForegroundColor Green

# ── Verify Resource Group Exists ──────────────────────────────────────

$rgCheckRaw = az group show --name $ResourceGroupName --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Resource group '$ResourceGroupName' not found. Run deploy.ps1 first."
    exit 1
}
$rgCheck = $rgCheckRaw | ConvertFrom-Json
Write-Host "Resource Group: $ResourceGroupName ($($rgCheck.location))" -ForegroundColor Green

# ── Discover Resources ──────────────────────────────────────────────

Write-Host "`n[1/3] Checking resource health..." -ForegroundColor Yellow

$resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json

# Find each resource type
$apim = $resources | Where-Object { $_.type -eq "Microsoft.ApiManagement/service" } | Select-Object -First 1
$intakeLogicApp = $resources | Where-Object { $_.type -eq "Microsoft.Logic/workflows" -and $_.name -like "*-intake" } | Select-Object -First 1
$routerLogicApp = $resources | Where-Object { $_.type -eq "Microsoft.Logic/workflows" -and $_.name -like "*-router" } | Select-Object -First 1
$serviceBus = $resources | Where-Object { $_.type -eq "Microsoft.ServiceBus/namespaces" } | Select-Object -First 1
$keyVault = $resources | Where-Object { $_.type -eq "Microsoft.KeyVault/vaults" } | Select-Object -First 1
$logAnalytics = $resources | Where-Object { $_.type -eq "Microsoft.OperationalInsights/workspaces" } | Select-Object -First 1
$grafana = $resources | Where-Object { $_.type -eq "Microsoft.Dashboard/grafana" } | Select-Object -First 1

$allHealthy = $true
$resourceChecks = @(
    @{ Name = "API Management"; Resource = $apim },
    @{ Name = "Logic App (Intake)"; Resource = $intakeLogicApp },
    @{ Name = "Logic App (Router)"; Resource = $routerLogicApp },
    @{ Name = "Service Bus"; Resource = $serviceBus },
    @{ Name = "Key Vault"; Resource = $keyVault },
    @{ Name = "Log Analytics"; Resource = $logAnalytics },
    @{ Name = "Grafana"; Resource = $grafana }
)

foreach ($check in $resourceChecks) {
    if ($check.Resource) {
        Write-Host "  $($check.Name): OK ($($check.Resource.name))" -ForegroundColor Green
        Add-CheckResult -Success $true
    } else {
        Write-Host "  $($check.Name): MISSING" -ForegroundColor Red
        $allHealthy = $false
        Add-CheckResult -Success $false
    }
}

if (-not $allHealthy) {
    Write-Warning "Some resources are missing. The demo may not work correctly."
}

# ── Get APIM Details ──────────────────────────────────────────────

Write-Host "`n[2/3] Retrieving APIM endpoint and subscription key..." -ForegroundColor Yellow

$gatewayUrl = $null
$referralEndpoint = $null
$subscriptionKey = $null

if ($apim) {
    try {
        $apimName = $apim.name

        $apimDetails = az apim show --name $apimName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        $gatewayUrl = $apimDetails.gatewayUrl
        $referralEndpoint = "$gatewayUrl/referrals/submit"

        # Get subscription key
        $subKey = az rest --method post `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/referral-subscription/listSecrets?api-version=2023-05-01-preview" `
            --output json 2>$null | ConvertFrom-Json

        $subscriptionKey = $subKey.primaryKey

        Write-Host "  Endpoint: $referralEndpoint" -ForegroundColor Green
        Write-Host "  Key: $subscriptionKey" -ForegroundColor Green
        Add-CheckResult -Success $true
    } catch {
        Write-Host "  APIM details retrieval: FAILED" -ForegroundColor Red
        Add-CheckResult -Success $false
    }
} else {
    Write-Host "  APIM details retrieval: SKIPPED (APIM resource missing)" -ForegroundColor Yellow
    Add-CheckResult -Success $false
}

# Get Grafana endpoint
$grafanaEndpoint = $null
if ($grafana) {
    try {
        $grafanaDetails = az rest --method get --uri "https://management.azure.com$($grafana.id)?api-version=2023-09-01" --output json 2>$null | ConvertFrom-Json
        $grafanaEndpoint = $grafanaDetails.properties.endpoint
        Write-Host "  Grafana:  $grafanaEndpoint" -ForegroundColor Green
        Add-CheckResult -Success $true
    } catch {
        Write-Host "  Grafana endpoint lookup via ARM: FAILED" -ForegroundColor Red
        $showGrafanaExtensionHelp = $true
        Add-CheckResult -Success $false
    }
}

# ── Cheat Sheet ──────────────────────────────────────────────

Write-Host "`n[3/3] Demo cheat sheet" -ForegroundColor Yellow

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " DEMO CHEAT SHEET" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n  Test Command:" -ForegroundColor White
if ($referralEndpoint -and $subscriptionKey) {
    Write-Host "  ./test-referral.ps1 -ApiEndpoint '$referralEndpoint' -SubscriptionKey '$subscriptionKey'" -ForegroundColor Yellow
} else {
    Write-Host "  Test command unavailable until APIM endpoint and key are resolved" -ForegroundColor Yellow
}

Write-Host "`n  KQL Queries:" -ForegroundColor White
Write-Host "  ── Logic App Runs ──" -ForegroundColor Gray
Write-Host '  AzureDiagnostics | where ResourceProvider == "MICROSOFT.LOGIC" | where Category == "WorkflowRuntime" | project TimeGenerated, resource_workflowName_s, status_s | order by TimeGenerated desc | take 20' -ForegroundColor DarkGray

Write-Host "`n  ── Service Bus Metrics ──" -ForegroundColor Gray
Write-Host '  AzureMetrics | where ResourceProvider == "MICROSOFT.SERVICEBUS" | where MetricName == "IncomingMessages" or MetricName == "OutgoingMessages" | summarize Total=sum(Total) by MetricName, Resource' -ForegroundColor DarkGray

Write-Host "`n  Grafana Dashboard:" -ForegroundColor White
if ($grafanaEndpoint) {
    Write-Host "  $grafanaEndpoint" -ForegroundColor Yellow
} elseif ($grafana) {
    Write-Host "  https://portal.azure.com/#@/resource$($grafana.id)/overview" -ForegroundColor Yellow
} else {
    Write-Host "  Grafana resource not found" -ForegroundColor Yellow
}

Write-Host "`n  Cleanup:" -ForegroundColor White
Write-Host "  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor Yellow

# ── Open Portal Pages ──────────────────────────────────────────────

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Opening Azure Portal Pages..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$portalBase = "https://portal.azure.com/#@/resource"

$urls = @(
    @{
        Label = "Resource Group Overview"
        Url   = "https://portal.azure.com/#@/resource/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/overview"
    },
    @{
        Label = "Intake Logic App — Run History"
        Url   = "$portalBase$($intakeLogicApp.id)/logicApp"
    },
    @{
        Label = "Router Logic App — Run History"
        Url   = "$portalBase$($routerLogicApp.id)/logicApp"
    },
    @{
        Label = "Service Bus — Queues"
        Url   = "$portalBase$($serviceBus.id)/queues"
    },
    @{
        Label = "Log Analytics — Logs"
        Url   = "$portalBase$($logAnalytics.id)/logs"
    },
    @{
        Label = "Grafana Dashboard"
        Url   = if ($grafanaEndpoint) { $grafanaEndpoint } elseif ($grafana) { "https://portal.azure.com/#@/resource$($grafana.id)/overview" } else { $null }
    }
)

foreach ($page in $urls) {
    if (-not $page.Url) { continue }
    Write-Host "  Opening: $($page.Label)" -ForegroundColor Gray
    Start-Process $page.Url
    Start-Sleep -Milliseconds 800
}

Write-Host "`n  All Portal pages opened in your default browser." -ForegroundColor Green
Write-Host "  Arrange them across your screens before starting the demo.`n" -ForegroundColor Gray

if ($showGrafanaExtensionHelp) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Azure CLI Grafana Extension Note" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Grafana lookup failed during this run. If you use 'az grafana ...' commands in this terminal:" -ForegroundColor White
    Write-Host "  az config set extension.use_dynamic_install=yes_without_prompt" -ForegroundColor Yellow
    Write-Host "  az extension add --name amg --upgrade" -ForegroundColor Yellow
    Write-Host "  # Optional if your org allows preview modules:" -ForegroundColor Gray
    Write-Host "  az config set extension.dynamic_install_allow_preview=true" -ForegroundColor DarkGray
    Write-Host ""
}

$statusRatio = if ($totalChecks -gt 0) { [double]$passedChecks / [double]$totalChecks } else { 0 }

$overallLabel = "RED"
$overallMessage = "Less than most checks passed"
$overallColor = "Red"

if ($statusRatio -eq 1) {
    $overallLabel = "GREEN"
    $overallMessage = "All checks passed; environment looks demo-ready"
    $overallColor = "Green"
} elseif ($statusRatio -ge 0.6) {
    $overallLabel = "YELLOW"
    $overallMessage = "Most checks passed; verify warnings before demo"
    $overallColor = "Yellow"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OVERALL STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Status : $overallLabel" -ForegroundColor $overallColor
Write-Host "  Checks : $passedChecks/$totalChecks" -ForegroundColor White
Write-Host "  Result : $overallMessage" -ForegroundColor $overallColor
Write-Host ""
