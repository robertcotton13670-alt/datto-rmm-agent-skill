# Function Reference

All functions from Nathan's DattoRMM-Toolkit. Source: `datto-rmm-toolkit/DattoRMM-Toolkit.ps1`

## Logging

### Write-Log
Structured logging to file + stdout.

```powershell
Write-Log -Message "Installing app" -Level INFO -LogFile "C:\custom.log"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Message | string | (required) | Log message |
| Level | string | INFO | INFO, WARN, ERROR, DEBUG |
| LogFile | string | auto-generated | Override log path |

Writes `[$timestamp] [$Level] $Message` to file and stdout. ERROR goes to Write-Error,
WARN to Write-Warning, DEBUG to Write-Verbose.

Log files go to `$env:ProgramData\CentraStage\Logs\component-{timestamp}.log`.

### Write-LogSection
Visual separator in logs.

```powershell
Write-LogSection -Title "Phase 2: Configuration"
# Output: ========== Phase 2: Configuration ==========
```

## Exit Codes

### Exit-Component
Clean exit with logging.

```powershell
Exit-Component -ExitCode 0 -Message "Done"
```

### Exit-Success / Exit-Failure / Exit-NotApplicable / Exit-RebootRequired
Convenience wrappers:

```powershell
Exit-Success "Installed successfully"              # exit 0
Exit-Failure "Download failed" -ExitCode 20        # exit 20
Exit-NotApplicable "Windows 10 required"           # exit 2
Exit-RebootRequired "Reboot to complete install"   # exit 4
```

## UDF Management

### Set-DattoUDF
Write to UDF 1-30 via registry + env var.

```powershell
Set-DattoUDF -UDF 5 -Value "BitLocker: Enabled"
# Returns: $true on success, $false on failure
```

### Get-DattoUDF
Read current UDF value.

```powershell
$val = Get-DattoUDF -UDF 5
```

### Set-DattoUDFTimestamp
Write UDF with timestamp prefix.

```powershell
Set-DattoUDFTimestamp -UDF 20 -Value "Cleanup: 4.2GB freed"
# Result: "2026-03-01 19:30 | Cleanup: 4.2GB freed"
```

## Environment Variables

### Get-DattoVariable
Read Datto site/component variable with prefix fallback.

```powershell
$val = Get-DattoVariable -Name "ApiKey"
```

Tries: `$Name`, `CS_$Name`, `cs_$Name`, `userdefined_$Name`.

### Get-RMMVariable
Read environment variable with type conversion.

```powershell
$threshold = Get-RMMVariable -Name 'Threshold' -Type Integer -Default 80
$enabled = Get-RMMVariable -Name 'FeatureEnabled' -Type Boolean -Default $false
$items = Get-RMMVariable -Name 'ServerList' -Type Array -Default @('server1')
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Name | string | (required) | Env var name |
| Type | string | String | String, Integer, Boolean, Double, Array |
| Default | any | $null | Fallback if not set or conversion fails |

Boolean truthy values: `true`, `1`, `yes`, `on`, `enabled`.
Array splits on commas and trims whitespace.

### Test-DattoAgent
Check if Datto RMM agent (CagService) is installed and running.

```powershell
if (-not (Test-DattoAgent)) { Exit-Failure "Agent not running" }
```

## User Context

### Get-LoggedOnUser
Get the interactive console user via explorer.exe ownership.

```powershell
$user = Get-LoggedOnUser
# Returns: PSObject with Username, Domain, FullName, SID, SessionId, ProfilePath
# Returns: $null if no interactive user
```

### Invoke-AsLoggedOnUser
Run a script block as the logged-on user via scheduled task.

```powershell
$result = Invoke-AsLoggedOnUser -ScriptBlock {
    param($AppName)
    Get-Process $AppName | Select Name, CPU
} -ArgumentList 'chrome' -Timeout 120
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ScriptBlock | scriptblock | (required) | Code to run as user |
| ArgumentList | object[] | $null | Arguments to pass |
| Timeout | int | 120 | Max seconds to wait |

Creates a scheduled task in the user's interactive session, captures output via Export-Clixml.

## Registry - All Users

### Get-UserRegistryPaths
Get registry hive paths for user registry manipulation.

```powershell
$paths = Get-UserRegistryPaths -Target All
# Returns array of objects:
#   SID, Username, HivePath, NtUserDat, NeedsMount, MountPoint
```

Target: `Current` (logged-on user only) or `All` (all profiles, mounts offline hives).

### Invoke-UserRegistryAction
Execute a script block against user registry hives. Auto-mounts/unmounts offline hives.

```powershell
$result = Invoke-UserRegistryAction -Target All -Action {
    param($HivePath, $UserInfo)
    Set-ItemProperty "$HivePath\SOFTWARE\MyApp" -Name 'Setting' -Value 1 -Force
}
# Returns: @{ Success = 5; Failed = 0 }
```

Handles: loaded vs offline hive detection, `reg.exe load`/`unload`, GC flush before unload.

## Software Detection

### Test-SoftwareInstalled
Registry-based software detection (32-bit + 64-bit uninstall keys). Never uses Win32_Product.

```powershell
$apps = Test-SoftwareInstalled -Name '*Chrome*'
$apps = Test-SoftwareInstalled -Name 'Google Chrome' -Exact -MinVersion '120.0'
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Name | string | (required) | Display name (supports wildcards unless -Exact) |
| MinVersion | string | $null | Minimum version filter |
| Exact | switch | $false | Exact name match |

Returns array of objects: DisplayName, DisplayVersion, Publisher, InstallDate,
UninstallString, Architecture.

## File Download

### Invoke-FileDownload
Download with TLS 1.2, retry, hash validation, and signature checking.

```powershell
$ok = Invoke-FileDownload -Url $url -OutputPath "$env:TEMP\app.msi" `
    -ExpectedHash 'ABC123...' -VerifySignature -MaxRetries 3
if (-not $ok) { Exit-Failure "Download failed" }
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Url | string | (required) | Download URL |
| OutputPath | string | (required) | Local save path |
| ExpectedHash | string | $null | SHA-256 hash to verify |
| VerifySignature | switch | $false | Check Authenticode |
| MaxRetries | int | 3 | Retry attempts |
| RetryDelaySec | int | 5 | Seconds between retries |
| TimeoutSec | int | 300 | Download timeout |

Uses System.Net.WebClient with system proxy support. Returns `$true`/`$false`.

## System Requirements

### Test-SystemRequirements
Validate prerequisites before running main logic.

```powershell
$reqs = Test-SystemRequirements -MinOSBuild 19041 -MinPSVersion 5.1 `
    -MinDiskSpaceGB 2 -RequireAdmin -RequiredServices @('Spooler','wuauserv')
if (-not $reqs.Passed) { Exit-NotApplicable $reqs.Details }
```

Returns: PSObject with Passed (bool), Failures (string[]), Details (string).

## Monitor Output

### Write-MonitorDiagnostic
Write a line inside the diagnostic block.

```powershell
Write-MonitorDiagnostic "Checking disk space..."
```

### Write-MonitorAlert
End monitor with alert status. Closes markers and exits with code 1.

```powershell
Write-MonitorAlert "CRITICAL: Disk space below 5%"
```

### Write-MonitorSuccess
End monitor with healthy status. Closes markers and exits with code 0.

```powershell
Write-MonitorSuccess "OK: All disks above 20% free"
```

Both Alert and Success close `<-End Diagnostic->`, emit `<-Start Result->`,
write `Status=$Message`, emit `<-End Result->`, and call `exit`.
