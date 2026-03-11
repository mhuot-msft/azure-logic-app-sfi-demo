# Copyright 2025 HACS Group
# Licensed under the Apache License, Version 2.0
#
# test-referral-soak.ps1 — Continuous low-volume referral sender for pre-demo Grafana warmup
# Purpose: Run before a demo to build up realistic dashboard data over time
# Usage: ./test-referral-soak.ps1 -ApiEndpoint <url> -SubscriptionKey <key> [-DurationMinutes 60] [-IntervalSeconds 45]

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionKey,

    [Parameter(Mandatory = $false)]
    [int]$DurationMinutes = 60,

    [Parameter(Mandatory = $false)]
    [int]$IntervalSeconds = 45,

    [Parameter(Mandatory = $false)]
    [double]$ErrorRate = 0.08
)

$ErrorActionPreference = "Stop"

# ── Synthetic Data Pools ──────────────────────────────────────────────────

$patients = @(
    @{ id = "PT-2025-00142"; name = "Sarah Mitchell" }
    @{ id = "PT-2025-00287"; name = "David Chen" }
    @{ id = "PT-2025-01034"; name = "Maria Gonzalez" }
    @{ id = "PT-2025-01199"; name = "James O'Brien" }
    @{ id = "PT-2025-01455"; name = "Aisha Patel" }
    @{ id = "PT-2025-01678"; name = "Robert Kim" }
    @{ id = "PT-2025-01890"; name = "Linda Thompson" }
    @{ id = "PT-2025-02001"; name = "Michael Johansson" }
    @{ id = "PT-2025-02234"; name = "Fatima Al-Rashid" }
    @{ id = "PT-2025-02567"; name = "Carlos Rivera" }
    @{ id = "PT-2025-02890"; name = "Emily Nakamura" }
    @{ id = "PT-2025-03012"; name = "William Okafor" }
    @{ id = "PT-2025-03345"; name = "Jennifer Kowalski" }
    @{ id = "PT-2025-03567"; name = "Hassan Demir" }
    @{ id = "PT-2025-03890"; name = "Rachel Bernstein" }
)

$referralTypes = @(
    @{ type = "Cardiology";          diagnoses = @(
        @{ code = "I25.10";  desc = "Atherosclerotic heart disease of native coronary artery" },
        @{ code = "I48.91";  desc = "Unspecified atrial fibrillation" },
        @{ code = "I50.9";   desc = "Heart failure, unspecified" }
    )}
    @{ type = "Orthopedics";         diagnoses = @(
        @{ code = "M17.11";  desc = "Primary osteoarthritis, right knee" },
        @{ code = "M75.10";  desc = "Rotator cuff tear, unspecified shoulder" },
        @{ code = "S72.001A"; desc = "Fracture of unspecified part of neck of right femur" }
    )}
    @{ type = "Physical Therapy";    diagnoses = @(
        @{ code = "M54.5";   desc = "Low back pain" },
        @{ code = "M79.3";   desc = "Panniculitis, unspecified" },
        @{ code = "G89.29";  desc = "Other chronic pain" }
    )}
    @{ type = "Neurology";           diagnoses = @(
        @{ code = "G43.909"; desc = "Migraine, unspecified, not intractable" },
        @{ code = "G40.909"; desc = "Epilepsy, unspecified, not intractable" },
        @{ code = "G20";     desc = "Parkinson's disease" }
    )}
    @{ type = "Gastroenterology";    diagnoses = @(
        @{ code = "K21.0";   desc = "Gastro-esophageal reflux disease with esophagitis" },
        @{ code = "K50.90";  desc = "Crohn's disease, unspecified, without complications" },
        @{ code = "K76.0";   desc = "Fatty liver, not elsewhere classified" }
    )}
    @{ type = "Pulmonology";         diagnoses = @(
        @{ code = "J44.1";   desc = "Chronic obstructive pulmonary disease with acute exacerbation" },
        @{ code = "J45.20";  desc = "Mild intermittent asthma, uncomplicated" },
        @{ code = "J84.10";  desc = "Pulmonary fibrosis, unspecified" }
    )}
    @{ type = "Endocrinology";       diagnoses = @(
        @{ code = "E11.65";  desc = "Type 2 diabetes mellitus with hyperglycemia" },
        @{ code = "E05.90";  desc = "Thyrotoxicosis, unspecified" },
        @{ code = "E21.0";   desc = "Primary hyperparathyroidism" }
    )}
    @{ type = "Dermatology";         diagnoses = @(
        @{ code = "L40.0";   desc = "Psoriasis vulgaris" },
        @{ code = "L20.9";   desc = "Atopic dermatitis, unspecified" },
        @{ code = "C43.9";   desc = "Malignant melanoma of skin, unspecified" }
    )}
)

$providers = @(
    "Dr. James Wilson, MD - Internal Medicine"
    "Dr. Emily Rodriguez, DO - Family Medicine"
    "Dr. Anand Krishnamurthy, MD - Emergency Medicine"
    "Dr. Catherine Dubois, MD - Family Medicine"
    "Dr. Omar Hassan, DO - Internal Medicine"
    "Dr. Patricia Yamamoto, MD - Urgent Care"
    "Dr. Steven Blackwell, DO - Family Medicine"
    "Dr. Nadia Volkov, MD - Internal Medicine"
)

$priorities = @(
    "urgent", "urgent",
    "high", "high", "high",
    "normal", "normal", "normal", "normal", "normal", "normal",
    "low", "low", "low", "low"
)

$noteTemplates = @(
    "Patient presents with worsening symptoms over the past {0} weeks. Current medications partially effective. Recommend specialist evaluation."
    "Referred for further workup. Initial labs and imaging reviewed. {0}-week follow-up recommended."
    "Chronic condition management. Patient stable but requires specialist input for treatment optimization. Duration: {0} weeks."
    "New onset symptoms. Patient evaluated in clinic, conservative management attempted for {0} weeks without improvement."
    "Post-hospitalization follow-up. Patient discharged {0} days ago, requires outpatient specialist care."
    "Screening referral per clinical guidelines. Patient has {0} risk factors identified."
    "Acute presentation requiring expedited specialist review. Symptoms duration: {0} days."
)

# ── Helper Functions ──────────────────────────────────────────────────────

function New-RandomReferral {
    $patient   = $patients | Get-Random
    $specialty = $referralTypes | Get-Random
    $diagnosis = $specialty.diagnoses | Get-Random
    $priority  = $priorities | Get-Random
    $provider  = $providers | Get-Random
    $template  = $noteTemplates | Get-Random
    $duration  = Get-Random -Minimum 1 -Maximum 12

    return @{
        patientId         = $patient.id
        patientName       = $patient.name
        referralType      = $specialty.type
        priority          = $priority
        diagnosis         = @{
            code        = $diagnosis.code
            description = $diagnosis.desc
        }
        referringProvider = $provider
        notes             = ($template -f $duration)
    }
}

function New-RandomInvalidReferral {
    $variant = Get-Random -Minimum 1 -Maximum 5
    switch ($variant) {
        1 { return @{ patientId = "PT-2025-99901"; notes = "Missing most required fields" } }
        2 { return @{ patientId = "PT-2025-99902"; patientName = "Test Invalid"; referralType = "Cardiology" } }
        3 { return @{ patientName = "No Patient ID"; priority = "urgent" } }
        4 { return @{ patientId = "PT-2025-99903"; patientName = "Bad Priority"; priority = "critical"; referralType = "Neurology" } }
    }
}

function Format-TimeSpan {
    param([TimeSpan]$Span)
    if ($Span.TotalHours -ge 1) {
        return "{0}h {1}m" -f [Math]::Floor($Span.TotalHours), $Span.Minutes
    }
    return "{0}m {1}s" -f $Span.Minutes, $Span.Seconds
}

# ── Main Execution ────────────────────────────────────────────────────────

$headers = @{
    "Content-Type"              = "application/json"
    "Ocp-Apim-Subscription-Key" = $SubscriptionKey
}

$startTime = Get-Date
$endTime   = $startTime.AddMinutes($DurationMinutes)

# Jitter range: send at interval +/- 40% to avoid perfectly regular spacing
$jitterMin = [Math]::Max(10, [int]($IntervalSeconds * 0.6))
$jitterMax = [int]($IntervalSeconds * 1.4)

$estimatedCount = [Math]::Ceiling(($DurationMinutes * 60) / $IntervalSeconds)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Healthcare Referral Soak Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Duration:     $DurationMinutes minutes (until $($endTime.ToString('HH:mm:ss')))" -ForegroundColor White
Write-Host "  Interval:     ~${IntervalSeconds}s (${jitterMin}s-${jitterMax}s with jitter)" -ForegroundColor White
Write-Host "  Est. total:   ~$estimatedCount referrals" -ForegroundColor White
Write-Host "  Error rate:   $([Math]::Round($ErrorRate * 100))%" -ForegroundColor White
Write-Host "  Endpoint:     $ApiEndpoint" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to stop early" -ForegroundColor Yellow
Write-Host ""

$sent       = 0
$succeeded  = 0
$failed     = 0
$errors     = 0

try {
    while ((Get-Date) -lt $endTime) {
        $now       = Get-Date
        $remaining = $endTime - $now
        $sent++

        # Decide if this should be an invalid referral
        $sendInvalid = ([double](Get-Random -Minimum 0 -Maximum 100) / 100.0) -lt $ErrorRate

        $timestamp = $now.ToString("HH:mm:ss")
        $countdown = Format-TimeSpan -Span $remaining

        if ($sendInvalid) {
            $referral = New-RandomInvalidReferral
            $priorityTag = "[INVALID]"
            $priorityColor = "Yellow"
            $specialtyLabel = "validation-test"
            $nameLabel = $referral.patientName ?? "n/a"
        } else {
            $referral = New-RandomReferral
            $priorityTag = "[$($referral.priority.ToUpper())]"
            $priorityColor = switch ($referral.priority) {
                "urgent" { "Red" }
                "high"   { "Magenta" }
                "normal" { "White" }
                "low"    { "Gray" }
            }
            $specialtyLabel = $referral.referralType
            $nameLabel = $referral.patientName
        }

        Write-Host "  [$timestamp]" -ForegroundColor DarkGray -NoNewline
        Write-Host " #$sent" -ForegroundColor Yellow -NoNewline
        Write-Host " $priorityTag" -ForegroundColor $priorityColor -NoNewline
        Write-Host " $specialtyLabel — $nameLabel" -ForegroundColor White -NoNewline

        $body = $referral | ConvertTo-Json -Depth 3

        try {
            $null = Invoke-RestMethod -Uri $ApiEndpoint -Method Post -Headers $headers -Body $body -StatusCodeVariable statusCode
            if ($sendInvalid) {
                Write-Host " -> $statusCode (unexpected)" -ForegroundColor Yellow
            } else {
                $succeeded++
                Write-Host " -> 202" -ForegroundColor Green
            }
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($sendInvalid -and $code -eq 400) {
                $errors++
                Write-Host " -> 400 (expected)" -ForegroundColor Green
            } else {
                $failed++
                Write-Host " -> $code FAILED" -ForegroundColor Red
            }
        }

        # Check if time remains before sleeping
        if ((Get-Date) -ge $endTime) { break }

        # Sleep with jitter
        $sleepSec = Get-Random -Minimum $jitterMin -Maximum $jitterMax
        $sleepUntil = (Get-Date).AddSeconds($sleepSec)
        if ($sleepUntil -gt $endTime) {
            $sleepSec = [Math]::Max(0, ($endTime - (Get-Date)).TotalSeconds)
        }

        # Show countdown during longer waits
        Write-Host "       next in ${sleepSec}s | $countdown remaining" -ForegroundColor DarkGray

        if ($sleepSec -gt 0) {
            Start-Sleep -Seconds $sleepSec
        }
    }
} finally {
    # Always show summary, even on Ctrl+C
    $elapsed = (Get-Date) - $startTime

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Soak Test Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Total sent:     $sent" -ForegroundColor White
    Write-Host "  Succeeded:      $succeeded" -ForegroundColor Green
    Write-Host "  Expected errors: $errors" -ForegroundColor Yellow
    Write-Host "  Failures:       $failed" -ForegroundColor Red
    Write-Host "  Elapsed:        $(Format-TimeSpan -Span $elapsed)" -ForegroundColor White
    Write-Host "  Avg rate:       1 per $([Math]::Round($elapsed.TotalSeconds / [Math]::Max(1, $sent), 0))s" -ForegroundColor White
    Write-Host ""
    Write-Host "  Grafana tips:" -ForegroundColor Cyan
    Write-Host "    - Log Analytics ingestion lag is 5-10 min" -ForegroundColor Gray
    Write-Host "    - Set time range to match soak duration" -ForegroundColor Gray
    Write-Host "    - Look for priority distribution and error rate patterns" -ForegroundColor Gray
    Write-Host ""
}
