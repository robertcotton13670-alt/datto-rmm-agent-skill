# Getting Started

## What This Skill Does

This is a knowledge pack for building Datto RMM components (Scripts, Applications, and Monitors). It encodes the rules, patterns, and gotchas that make the difference between a component that works in a lab and one that works across thousands of endpoints in production.

It works two ways:
1. **AI agents** read the skill files and apply the rules automatically when you ask them to build components
2. **Humans** use the templates, guides, and references as documentation

## Prerequisites

- **PowerShell 5.1+** (ships with Windows 10/Server 2016+)
- **Datto RMM access** (to deploy components)
- **A text editor** (VS Code recommended -- save as UTF-8 or ASCII)

## Using with an AI Agent

### OpenClaw / Claude Code / Codex

1. Copy this entire repo into your agent's skills directory:
   ```
   your-workspace/skills/datto-rmm-dev/
   ```
2. The agent auto-detects it via the SKILL.md frontmatter
3. Ask naturally:
   - "Create a Datto RMM monitor that checks if BitLocker is enabled"
   - "Build a component that installs Chrome silently"
   - "Write a monitor for disk space with a configurable threshold"

The agent will:
- Use the correct template (component vs monitor)
- Follow the monitor output contract
- Use Write-Host for monitors, proper exit codes
- Embed functions instead of dot-sourcing
- Avoid Win32_Product, use ASCII only
- Validate the result

## Using as a Human Reference

Read the guides in order:
1. This page (you're here)
2. [Component Guide](component-guide.md) for Scripts and Applications
3. [Monitor Guide](monitor-guide.md) for Monitors

Then use the references as needed:
- [Function Reference](../references/function-reference.md) -- all toolkit functions
- [Component Patterns](../references/component-patterns.md) -- download, attachment, error handling
- [Monitor Contract](../references/monitor-contract.md) -- the exact output format
- [PowerShell Pitfalls](../references/powershell-pitfalls.md) -- PS 5.1 gotchas

## Creating Your First Component

### Step 1: Copy the Template

```powershell
Copy-Item assets/templates/component.ps1 my-first-component.ps1
```

### Step 2: Fill in the Header

Update the synopsis, description, and document your environment variables:

```powershell
<#
.SYNOPSIS
    Install-TeamViewer - Datto RMM Component

.DESCRIPTION
    Silently installs TeamViewer Host with a custom configuration.

.INPUTS
    Environment Variables:
    - $env:ConfigID  [String]  TeamViewer assignment ID (required)
#>
```

### Step 3: Add Your Logic

Inside the `try` block, implement your component:

```powershell
try {
    Write-Log "Starting TeamViewer installation..."

    $configId = Get-RMMVariable -Name 'ConfigID' -Type String
    if ([string]::IsNullOrWhiteSpace($configId)) {
        Exit-Failure "ConfigID environment variable is required"
    }

    # Download installer
    $installerUrl = "https://download.teamviewer.com/download/TeamViewer_Host_Setup.exe"
    $installerPath = "$env:TEMP\TeamViewer_Host_Setup.exe"

    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    # Silent install
    $args = "/S /norestart /customconfig $configId"
    $proc = Start-Process -FilePath $installerPath -ArgumentList $args -Wait -PassThru
    Write-Log "Installer exit code: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0) {
        Exit-Failure "Installation failed with exit code $($proc.ExitCode)"
    }

    Exit-Success "TeamViewer installed successfully"
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Level ERROR
    Exit-Failure "Failed: $($_.Exception.Message)"
}
```

### Step 4: Validate

```powershell
.\scripts\validate-component.ps1 -Path my-first-component.ps1 -Type Component
```

### Step 5: Deploy

Upload to Datto RMM as a Script or Application component and test on a single endpoint first.

## Creating Your First Monitor

### Step 1: Copy the Template

```powershell
Copy-Item assets/templates/monitor.ps1 my-first-monitor.ps1
```

### Step 2: Implement the Check

```powershell
Write-Host '<-Start Diagnostic->'
Write-MonitorDiagnostic "Disk Space Monitor"
Write-MonitorDiagnostic "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    $threshold = Get-RMMVariable -Name 'Threshold' -Type Integer -Default 10

    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $alerts = @()

    foreach ($drive in $drives) {
        $freePercent = [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 1)
        Write-MonitorDiagnostic "$($drive.DeviceID) $freePercent% free ($([math]::Round($drive.FreeSpace/1GB, 1)) GB)"

        if ($freePercent -lt $threshold) {
            $alerts += "$($drive.DeviceID) at $freePercent%"
        }
    }

    if ($alerts.Count -gt 0) {
        Write-MonitorAlert "CRITICAL: Low disk space - $($alerts -join ', ')"
    }

    Write-MonitorSuccess "OK: All drives above $threshold% free"
}
catch {
    Write-MonitorDiagnostic "ERROR: $($_.Exception.Message)"
    Write-MonitorAlert "CRITICAL: $($_.Exception.Message)"
}
```

### Step 3: Validate

```powershell
.\scripts\validate-component.ps1 -Path my-first-monitor.ps1 -Type Monitor
```

### Step 4: Test Locally

Run as Administrator to simulate SYSTEM context. Check that the output matches the marker format.

### Step 5: Deploy

Create a new Monitor component in Datto RMM. Set the Output Variable to `Status`. Deploy to a test group first.
