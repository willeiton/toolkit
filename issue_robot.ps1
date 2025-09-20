# =====================================================================
# PowerShell Script: GitLab Issue + Local Folder Automation
# Author: Willian Leiton
# Version: 1.0
#
# Description:
#   This script automates the creation of GitLab issues and the setup
#   of corresponding local development folders. It also renames files
#   inside the folder based on the issue ID and shows a Windows toast
#   notification when finished.
#
# Requirements:
#   - PowerShell 7+
#   - BurntToast module (for notifications)
#   - GitLab Personal Access Token (PAT) with API scope
# =====================================================================

# ---------------------------
# CONFIGURATION
# ---------------------------
$gitlabUrl   = "<your_gitlab_url>"             # Example: "https://gitlab.com"
$projectId   = "<your_project_id>"             # Example: "12345678"
$token       = "<your_gitlab_pat>"             # Secure GitLab Personal Access Token
$description = Get-Content "<path_to_description_file>" -Raw  # Markdown file with issue description

# Define issues to create (title, labels, estimated hours)
$issues = @(
    @{
        title       = "Example: Implement authentication module"
        labels      = @("Backend", "Security")
        estimateHrs = 10
    },
    @{
        title       = "Example: Update UI for dashboard"
        labels      = @("Frontend", "UI/UX")
        estimateHrs = 5
    }
)

# ---------------------------
# GITLAB API SETUP
# ---------------------------
$uri = "$gitlabUrl/api/v4/projects/$projectId/issues"

$headers = @{
    "PRIVATE-TOKEN" = $token
    "Content-Type"  = "application/json"
}

# ---------------------------
# MAIN LOOP – ISSUE CREATION
# ---------------------------
foreach ($issue in $issues) {
    # Always include "Improvement" plus any custom labels
    $allLabels = @("Improvement") + $issue.labels

    # Build request body
    $body = @{
        title        = $issue.title
        description  = $description
        labels       = ($allLabels -join ",")
    } | ConvertTo-Json -Depth 10

    # Create issue in GitLab
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

    # Apply time estimate (hours → GitLab duration string)
    if ($issue.estimateHrs -gt 0) {
        $duration = "$($issue.estimateHrs)h"
        $timeUri  = "$gitlabUrl/api/v4/projects/$projectId/issues/$($response.iid)/time_estimate?duration=$duration"
        Invoke-RestMethod -Uri $timeUri -Method Post -Headers $headers | Out-Null
    }

    # Store issue ID
    $issueId = $response.iid
    Write-Output "Created Issue ID: $issueId"

    # ---------------------------
    # LOCAL FOLDER CREATION
    # ---------------------------
    $source = "<path_to_template_folder>"        # Folder with template files
    $destinationRoot = "<path_to_target_root>"   # Base path where new issue folders go
    $destination = Join-Path $destinationRoot $issueId

    # Create destination folder (if not exists)
    if (-not (Test-Path $destination)) {
        New-Item -Path $destination -ItemType Directory | Out-Null
    }

    # Copy template contents into issue folder
    Get-ChildItem -Path $source -Force | ForEach-Object {
        $src = $_.FullName
        $target = Join-Path $destination $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -Path $src -Destination $target -Recurse -Force
        } else {
            Copy-Item -Path $src -Destination $destination -Force
        }
    }

    # ---------------------------
    # FILE RENAMING
    # ---------------------------
    Get-ChildItem -Path $destination -Recurse -File | ForEach-Object {
        $oldFullPath = $_.FullName
        $ext = $_.Extension
        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)

        # Normalize whitespace and hyphens
        $base = $base -replace '\s+', ' '
        $base = $base -replace '\s*-\s*', '-'
        $base = $base.Trim()

        # Insert issueId into filenames containing "issue"
        if ($base -match '(?i)issue-') {
            $newBase = $base -replace '(?i)issue-', ('Issue-' + $issueId)
        }
        elseif ($base -match '(?i)issue\b') {
            $newBase = $base -replace '(?i)issue\b', ('Issue-' + $issueId)
        }
        else {
            $newBase = $base
        }

        # Apply rename if different
        $newName = "$newBase$ext"
        if ($newName -ne $_.Name) {
            Rename-Item -LiteralPath $oldFullPath -NewName $newName -Force -ErrorAction SilentlyContinue
        }
    }

    # ---------------------------
    # DESKTOP NOTIFICATION
    # ---------------------------
    Import-Module BurntToast -ErrorAction Stop

    $path = Join-Path $destinationRoot $issueId
    $button = New-BTButton -Content "Open Folder" -Arguments $path

    New-BurntToastNotification `
        -Text "Issue $issueId created successfully.", "Click to open folder." `
        -Button $button
}
