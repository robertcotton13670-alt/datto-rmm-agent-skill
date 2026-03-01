# Component Development Guide

This guide covers building Datto RMM **Scripts** and **Applications** (not Monitors -- see the [Monitor Guide](monitor-guide.md) for those).

## Component Categories

### Applications

- **Timeout:** 30 minutes
- **Use for:** Software installations, large deployments, multi-step provisioning
- **Exit codes:** 0=success, 3010=reboot required, 1641=reboot initiated
- **Convertible:** Can convert to/from Scripts

### Scripts

- **Timeout:** Flexible (configurable)
- **Use for:** Automation tasks, config changes, maintenance, cleanup
- **Exit codes:** 0=success, 1=warnings, 2=errors
- **Convertible:** Can convert to/from Applications

Both run as **NT AUTHORITY\SYSTEM** and must be non-interactive (no UI prompts).

## Template Walkthrough

The component template (`assets/templates/component.ps1`) gives you:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    [Component Name] - Datto RMM Component
.DESCRIPTION
    [What it does]
.COMPONENT
    Category: Scripts | Applications
.INPUTS
    Environment Variables:
    - $env:VariableName  [String]  Description (required/optional)
.NOTES
    Author: Nathan Ash
    Version: 1.0.0
#>
```

The header documents everything someone needs to know to use the component in Datto -- what variables to set, what category to use, what it does.

Below the header, the template has three regions:

1. **TLS 1.2** -- Set at the top for any web requests
2. **TOOLKIT** -- Paste functions you need from the DattoRMM-Toolkit
3. **MAIN** -- Your logic in a try/catch block

## Environment Variables

Datto RMM injects variables as environment variables before your script runs. There are three sources:

| Source | Scope | Example |
|--------|-------|---------|
| Component variables | Per-component | `$env:InstallPath` |
| Site variables | Per-site | `$env:SiteApiKey` |
| Account variables | Global | `$env:CompanyName` |

### Reading Variables

```powershell
# Direct access
$server = $env:ServerURL

# With type conversion and defaults (recommended)
$threshold = Get-RMMVariable -Name 'Threshold' -Type Integer -Default 80
$enabled = Get-RMMVariable -Name 'FeatureEnabled' -Type Boolean -Default $false
$servers = Get-RMMVariable -Name 'ServerList' -Type Array -Default @('server1')
```

### Validating Required Variables

Always validate early -- fail fast with a clear message:

```powershell
$apiKey = $env:ApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Exit-Failure "Required variable 'ApiKey' is not set. Configure it in the Datto component."
}
```

### Secure Variables

For sensitive values (API keys, passwords), use Datto's secure variable feature. These are masked in logs and the UI. Access them the same way: `$env:SecureVarName`.

## File Attachments

Datto copies attached files into the script's working directory before execution.

### How It Works

1. You attach files to the component in the Datto RMM UI
2. When the component runs, those files are in the current directory
3. Reference them by filename -- no absolute paths

```powershell
# The file is right here in the working directory
$config = "settings.json"
if (Test-Path $config) {
    $settings = Get-Content $config | ConvertFrom-Json
}
```

### Always Validate

```powershell
$installer = "myapp-setup.msi"
if (-not (Test-Path $installer)) {
    Exit-Failure "Required attachment '$installer' not found. Ensure it's attached to the component."
}
```

### When to Attach vs Download

| Use Attachment | Use Download |
|----------------|-------------|
| Fixed-version installers | Latest version from vendor URL |
| Config files, certificates, licenses | Large files (>50MB) |
| Offline/air-gapped endpoints | Frequently updated files |
| Custom scripts or tools | Files with stable download URLs + signatures |

## Download Best Practices

### Always Set TLS 1.2

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

Older Windows systems default to TLS 1.0/1.1, which most CDNs reject.

### Validate Downloads

```powershell
# Hash validation
$expectedHash = 'ABC123DEF456...'
$actualHash = (Get-FileHash -Path $outFile -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash.ToUpper()) {
    Write-Log "Hash mismatch! Expected: $expectedHash Got: $actualHash" -Level ERROR
    Remove-Item $outFile -Force
    Exit-Failure "Download integrity check failed"
}

# Authenticode signature (for .exe, .msi, .dll)
$sig = Get-AuthenticodeSignature -FilePath $outFile
if ($sig.Status -ne 'Valid') {
    Write-Log "Authenticode failed: $($sig.Status)" -Level ERROR
    Remove-Item $outFile -Force
    Exit-Failure "Signature verification failed"
}
```

### Large Files (>1GB)

Use BITS transfer -- it handles interruption, resume, and bandwidth throttling:

```powershell
Start-BitsTransfer -Source $url -Destination $outFile -Priority Foreground
```

### Retry Pattern

```powershell
$maxRetries = 3
for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop
        break
    }
    catch {
        Write-Log "Download attempt $i failed: $($_.Exception.Message)" -Level WARN
        if ($i -eq $maxRetries) { throw }
        Start-Sleep -Seconds ($i * 5)
    }
}
```

Or use the toolkit's `Invoke-FileDownload` which handles TLS, retry, hash, and signature in one call.

## Error Handling

### The Standard Pattern

Every component should wrap its main logic in try/catch:

```powershell
try {
    Write-Log "Starting operation..."

    # Validate prerequisites
    # Do the work
    # Report success

    Exit-Success "Operation completed"
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level DEBUG
    Exit-Failure "Operation failed: $($_.Exception.Message)"
}
```

### Exit Codes

| Code | Toolkit Function | Meaning |
|------|-----------------|---------|
| 0 | `Exit-Success` | Success |
| 1 | `Exit-Failure` | General failure |
| 2 | `Exit-NotApplicable` | Prerequisite not met |
| 4 | `Exit-RebootRequired` | Reboot needed to complete |

For Applications specifically: 3010 = reboot required, 1641 = reboot initiated (these are MSI conventions).

### Prerequisite Checking

```powershell
$reqs = Test-SystemRequirements -MinPSVersion 5.1 -MinDiskSpaceGB 2 -RequireAdmin
if (-not $reqs.Passed) {
    Exit-NotApplicable $reqs.Details
}
```

## SYSTEM Context Gotchas

Components run as NT AUTHORITY\SYSTEM. This trips people up:

### `$env:USERPROFILE` Is Wrong

```powershell
# Under SYSTEM, this is C:\Windows\system32\config\systemprofile
$env:USERPROFILE  # NOT the logged-in user!

# To get the actual user's profile:
$user = Get-LoggedOnUser
if ($user) {
    $desktop = "$($user.ProfilePath)\Desktop"
}
```

### No Network Identity

SYSTEM has no network credentials. If you need a network share:

```powershell
# Map with explicit credentials
New-PSDrive -Name "Z" -PSProvider FileSystem -Root "\\server\share" `
    -Credential (New-Object PSCredential("DOMAIN\user", (ConvertTo-SecureString "pass" -AsPlainText -Force)))
```

### Can't See the User's Desktop

SYSTEM runs in session 0. The user is in session 1+. Processes started by SYSTEM are invisible to the user.

## User-Context Operations

When you need to touch user-specific things (HKCU, AppData, user-visible processes):

### Run Code as the Logged-In User

```powershell
$result = Invoke-AsLoggedOnUser -ScriptBlock {
    param($Setting)
    Set-ItemProperty "HKCU:\Software\MyApp" -Name "Config" -Value $Setting -Force
} -ArgumentList 'enabled'
```

This creates a scheduled task in the user's session, runs the code, and captures output.

### Modify All User Registry Hives

For settings that should apply to every user (including ones not currently logged in):

```powershell
Invoke-UserRegistryAction -Target All -Action {
    param($HivePath, $UserInfo)
    $path = "$HivePath\SOFTWARE\MyApp"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name 'Configured' -Value 1 -Type DWord -Force
}
```

This automatically mounts offline hives, applies the change, and unmounts them.

## Testing Locally

### 1. Run as Administrator

```powershell
# Simulate SYSTEM context (closest approximation)
powershell -ExecutionPolicy Bypass -File my-component.ps1
```

### 2. Set Environment Variables

```powershell
$env:ServerURL = "https://example.com"
$env:Threshold = "80"
powershell -ExecutionPolicy Bypass -File my-component.ps1
```

### 3. Check Exit Code

```powershell
powershell -ExecutionPolicy Bypass -File my-component.ps1; echo "Exit: $LASTEXITCODE"
```

### 4. Check Logs

Components log to `$env:ProgramData\CentraStage\Logs\`:

```powershell
Get-ChildItem "$env:ProgramData\CentraStage\Logs\component-*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    Get-Content
```

### 5. Validate

```powershell
.\scripts\validate-component.ps1 -Path my-component.ps1 -Type Component
```

## Deploying to Datto RMM

1. **Create component** -- In Datto RMM, choose Script or Application category
2. **Set variables** -- Define component variables with names, types, and defaults
3. **Attach files** -- Upload any files the component needs
4. **Paste script** -- Copy your component into the editor
5. **Save and test** -- Run on a single test endpoint first
6. **Check activity log** -- Verify stdout shows your Write-Log output and correct exit code
7. **Review UDFs** -- If you wrote UDFs, check they appear on the device dashboard
8. **Schedule or deploy** -- Set up scheduled runs or deploy to target sites

### Pro Tips

- **Test on one endpoint first.** Always. Even if you're sure it works.
- **Check the activity log.** Datto captures stdout -- your Write-Log output appears here.
- **Use UDFs for visibility.** Write status to a UDF so you can see results on the dashboard without drilling into activity logs.
- **Version your components.** Include a version in the header and log it at startup. Makes troubleshooting much easier.
