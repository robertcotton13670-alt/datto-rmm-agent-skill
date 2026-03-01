# Monitor Development Guide

## Why Monitors Are Different

Monitors aren't just "components that check things." They have fundamentally different constraints:

| | Components (Scripts/Applications) | Monitors |
|---|---|---|
| **Output** | Write-Output, Write-Host, anything | Write-Host **only** |
| **Timeout** | 30 min (Applications) | <3 sec hard limit, <200ms target |
| **Exit codes** | 0=success, various for errors | 0=healthy, 1=alert (binary) |
| **Category** | Convertible between Script/App | **Immutable** -- can't change after creation |
| **Dependencies** | Can dot-source, import modules | Must be **self-contained** |
| **Execution** | On-demand or scheduled | Runs every 5-30 minutes continuously |

Get any of these wrong and your monitor silently fails with "no data" in the Datto dashboard.

## The Output Contract

Datto's monitor parser looks for specific text markers in stdout. Here's what it expects:

```
+------------------------------------------+
|  <-Start Diagnostic->                    |  <-- First line of output
|  Monitor: Disk Space Check               |
|  Time: 2026-03-01 14:30:00              |
|  C: 45.2% free (89.3 GB)               |
|  D: 78.1% free (234.5 GB)              |  <-- Diagnostic info (for humans)
|  <-End Diagnostic->                      |
|  <-Start Result->                        |
|  Status=OK: All drives above 10% free   |  <-- The ONLY line Datto parses
|  <-End Result->                          |
+------------------------------------------+
```

### The Flow

```
Start
  |
  v
Write-Host '<-Start Diagnostic->'
  |
  v
[Your check logic -- Write-Host for each finding]
  |
  v
Is everything healthy?
  |          |
  YES        NO
  |          |
  v          v
Write-MonitorSuccess    Write-MonitorAlert
"OK: details"           "CRITICAL: details"
  |                       |
  v                       v
exit 0                  exit 1
```

### Rules

1. **First output line** must be `Write-Host '<-Start Diagnostic->'`
2. **Diagnostic block** contains human-readable troubleshooting info
3. **Result block** contains exactly ONE `Status=` line
4. **No spaces around `=`** -- `Status=OK` not `Status = OK`
5. **Exit code** matches the status: 0 for healthy, 1 for alert

## Write-Host vs Write-Output

This is the #1 cause of broken monitors. Here's why:

```
PowerShell Output Streams:
                                           Datto Captures?
  Write-Output  --> Success Stream (1) --> Maybe (unreliable)
  Write-Host    --> Information Stream --> YES (always)
  Write-Error   --> Error Stream (2)   --> No (goes to stderr)
  Write-Warning --> Warning Stream (3) --> No
  Write-Verbose --> Verbose Stream (4) --> No
```

`Write-Output` puts objects on the pipeline. Datto's monitor parser may not see them, resulting in "no data" alerts on your dashboard. `Write-Host` writes directly to the console host, which Datto captures reliably.

**Rule: Every single output statement in a monitor must be Write-Host.**

### Wrong

```powershell
# These all cause problems in monitors:
Write-Output "Check passed"
"Check passed"                    # Implicit Write-Output!
$result                           # Also implicit Write-Output!
Write-Error "Something failed"
Write-Warning "Low disk space"
```

### Right

```powershell
Write-Host "Check passed"
Write-MonitorDiagnostic "Check passed"   # Wrapper around Write-Host
Write-MonitorSuccess "OK: Check passed"  # Closes markers + exits
Write-MonitorAlert "CRITICAL: Failed"    # Closes markers + exits
```

## Helper Functions

Embed these in every monitor. Do **not** dot-source them from external files.

### Write-MonitorDiagnostic

Writes a line inside the diagnostic block:

```powershell
function Write-MonitorDiagnostic {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-Host $Message
}
```

It's a thin wrapper around Write-Host. Its value is readability -- when reviewing code, you can instantly see what's diagnostic output vs other logic.

### Write-MonitorAlert / Write-MonitorSuccess

These **terminate the monitor**. They close the diagnostic block, write the result, and exit:

```powershell
function Write-MonitorAlert {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-Host '<-End Diagnostic->'
    Write-Host '<-Start Result->'
    Write-Host "Status=$Message"
    Write-Host '<-End Result->'
    exit 1
}

function Write-MonitorSuccess {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-Host '<-End Diagnostic->'
    Write-Host '<-Start Result->'
    Write-Host "Status=$Message"
    Write-Host '<-End Result->'
    exit 0
}
```

> ⚠️ These call `exit`. Code after them never runs. Call them exactly once.

## Performance

Monitors run every 5-30 minutes across potentially thousands of endpoints. Slow monitors create real problems:

- **<200ms** -- Target. Your monitor is a good citizen.
- **<1s** -- Acceptable. Won't cause issues.
- **1-3s** -- Warning zone. Optimize if possible.
- **>3s** -- Datto may kill it. Fix required.

### Measuring Performance

```powershell
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ... your check logic ...

Write-MonitorDiagnostic "Execution time: $($stopwatch.ElapsedMilliseconds)ms"
```

### Performance Tips

| Slow | Fast |
|------|------|
| `Get-WmiObject Win32_Product` | `Test-SoftwareInstalled` (registry) |
| `Get-WmiObject Win32_Service` | `Get-Service` |
| `Invoke-WebRequest` | `[System.Net.WebClient]` |
| `Get-CimInstance` with complex filters | Direct registry reads |
| Loading entire modules | Embed only needed functions |

## Common Mistakes

### 1. Using Write-Output

```powershell
# WRONG - "no data" in Datto
Write-Output "Service is running"

# RIGHT
Write-Host "Service is running"
```

### 2. Multiple Status Lines

```powershell
# WRONG - Datto sees multiple Status= lines
foreach ($check in $checks) {
    if ($check.Failed) {
        Write-MonitorAlert "CRITICAL: $($check.Name) failed"
    }
}
Write-MonitorSuccess "OK: All passed"

# RIGHT - Collect results, emit once
$failures = @()
foreach ($check in $checks) {
    if ($check.Failed) { $failures += $check.Name }
}
if ($failures.Count -gt 0) {
    Write-MonitorAlert "CRITICAL: Failed: $($failures -join ', ')"
}
Write-MonitorSuccess "OK: All $($checks.Count) checks passed"
```

### 3. Missing Start Diagnostic Marker

```powershell
# WRONG - No opening marker
Write-Host "Checking services..."
Write-MonitorSuccess "OK"

# RIGHT
Write-Host '<-Start Diagnostic->'
Write-Host "Checking services..."
Write-MonitorSuccess "OK"
```

### 4. Dot-Sourcing External Files

```powershell
# WRONG - Monitor must be self-contained
. "$PSScriptRoot\helpers.ps1"

# RIGHT - Embed the functions directly
function Write-MonitorDiagnostic { ... }
function Write-MonitorAlert { ... }
function Write-MonitorSuccess { ... }
```

### 5. Not Handling Edge Cases

```powershell
# WRONG - Crashes if no user logged in
$user = Get-LoggedOnUser
Write-Host "User: $($user.Username)"  # NullReferenceException!

# RIGHT
$user = Get-LoggedOnUser
if ($null -eq $user) {
    Write-MonitorDiagnostic "No user currently logged in"
    Write-MonitorSuccess "OK: Check skipped (no user session)"
}
```

## Testing Monitors Locally

### 1. Run as Administrator

Monitors run as SYSTEM. Running as admin is the closest local approximation:

```powershell
# In an elevated PowerShell prompt:
powershell -ExecutionPolicy Bypass -File my-monitor.ps1
```

### 2. Check the Output

Verify the output matches the marker contract:

```
<-Start Diagnostic->
...your diagnostic lines...
<-End Diagnostic->
<-Start Result->
Status=OK: your message
<-End Result->
```

### 3. Check the Exit Code

```powershell
powershell -ExecutionPolicy Bypass -File my-monitor.ps1; echo "Exit: $LASTEXITCODE"
```

Expected: `0` for healthy, `1` for alert.

### 4. Simulate Environment Variables

```powershell
$env:Threshold = "85"
powershell -ExecutionPolicy Bypass -File my-monitor.ps1
Remove-Item Env:\Threshold
```

### 5. Validate

```powershell
.\scripts\validate-component.ps1 -Path my-monitor.ps1 -Type Monitor
```

## Deploying to Datto RMM

1. **Create component** -- In Datto RMM, create a new component with category **Monitor**
2. **Set Output Variable** -- Default is `Status`. Must match the variable name in your script's result line
3. **Paste script** -- Copy your monitor script into the component editor
4. **Set schedule** -- Typically every 15 or 30 minutes
5. **Deploy to test group** -- Always test on a small group first
6. **Verify in dashboard** -- Check that the Status column shows your expected output
7. **Set alert thresholds** -- Configure what Status values trigger alerts (e.g., anything starting with "CRITICAL")
8. **Roll out** -- Deploy to production sites
