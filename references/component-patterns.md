# Component Patterns

Best practices for Datto RMM components (Scripts and Applications category).

## Download Patterns

### TLS 1.2 Enforcement

Always set TLS 1.2 at the top of any component that downloads files:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

Older Windows systems default to TLS 1.0/1.1 which most CDNs reject.

### Hash Validation

```powershell
$expectedHash = 'ABC123...'
$actualHash = (Get-FileHash -Path $outFile -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash.ToUpper()) {
    Write-Log "SHA-256 mismatch! Expected: $expectedHash Got: $actualHash" -Level ERROR
    Remove-Item $outFile -Force
    exit 1
}
```

### Authenticode Signature Verification

```powershell
$sig = Get-AuthenticodeSignature -FilePath $outFile
if ($sig.Status -ne 'Valid') {
    Write-Log "Authenticode check failed: $($sig.Status)" -Level ERROR
    Remove-Item $outFile -Force
    exit 1
}
```

Only works on signable file types (.exe, .msi, .dll, .ps1, .cab, .msp).

### Retry Pattern

Use `Invoke-FileDownload` from the toolkit, or manually:

```powershell
$maxRetries = 3
for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop
        break
    }
    catch {
        if ($i -eq $maxRetries) { throw }
        Start-Sleep -Seconds ($i * 5)
    }
}
```

### Proxy Awareness

Datto agent may use a proxy. Read from agent config:

```powershell
[xml]$config = Get-Content "${env:ProgramFiles(x86)}\CentraStage\CagService.exe.config"
$proxyIp = ($config.configuration.appSettings.add | Where-Object { $_.key -eq 'ProxyIp' }).value
$proxyPort = ($config.configuration.appSettings.add | Where-Object { $_.key -eq 'ProxyPort' }).value
```

Or use system proxy:

```powershell
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$webClient.Proxy = $proxy
```

### Large File Downloads (BITS)

For files over 1GB, use BITS transfer instead of Invoke-WebRequest. BITS handles network interruption, resume, and bandwidth throttling automatically:

```powershell
# Simple BITS download
Start-BitsTransfer -Source $url -Destination $outFile -Priority Foreground

# With error handling
try {
    $job = Start-BitsTransfer -Source $url -Destination $outFile -Priority Foreground -ErrorAction Stop
    Write-Log "Download complete: $outFile" -Level SUCCESS
}
catch {
    Write-Log "BITS download failed: $($_.Exception.Message)" -Level ERROR
    # Fallback to Invoke-WebRequest if BITS fails
    Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop
}
```

### When to Download vs Attach

| Scenario | Use |
|----------|-----|
| Static installer, known version | File Attachment |
| Always-latest from vendor (stable URL + signature) | Download |
| Offline/air-gapped endpoints | File Attachment |
| Large files that change often | Download + hash validation |
| Config files, scripts, licenses | File Attachment |

## File Attachment Patterns

### How Attachments Work

Files attached to a Datto component are copied into the script's working directory before execution.
Reference them by filename only -- no absolute paths needed.

```powershell
# Correct -- direct filename reference
$installer = "myapp-setup.msi"
if (Test-Path $installer) {
    Start-Process msiexec.exe -ArgumentList "/i", $installer, "/quiet" -Wait
}
```

### When to Use Attachments vs Downloads

| Use Attachment | Use Download |
|----------------|-------------|
| Fixed-version installers | Latest version from vendor URL |
| Config files, certificates | Large files (>50MB) |
| License files | Frequently updated files |
| Custom scripts/tools | Files with stable download URLs |

### Validate Attachment Existence

Always check before using:

```powershell
$configFile = "settings.json"
if (-not (Test-Path $configFile)) {
    Write-Log "Required attachment '$configFile' not found in working directory" -Level ERROR
    exit 1
}
```

## Environment Variable Handling

Datto RMM injects site, account, and component variables as environment variables.

### Reading Variables

```powershell
# Direct access
$serverUrl = $env:ServerURL

# With type conversion and defaults (toolkit function)
$threshold = Get-RMMVariable -Name 'Threshold' -Type Integer -Default 80
$enabled = Get-RMMVariable -Name 'FeatureEnabled' -Type Boolean -Default $false
$targets = Get-RMMVariable -Name 'TargetList' -Type Array -Default @('default')
```

### Required Variable Validation

```powershell
$apiKey = $env:ApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Log "Required variable 'ApiKey' not set" -Level ERROR
    exit 1
}
```

## Error Handling

### Standard Try/Catch Pattern

```powershell
try {
    # Main logic
    Write-Log "Starting operation..."
    # ...
    Exit-Success "Operation completed"
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level DEBUG
    Exit-Failure "Operation failed: $($_.Exception.Message)"
}
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General failure |
| 2 | Not applicable / prereq not met |
| 3 | Timeout |
| 4 | Reboot required |
| 5 | Partial success |
| 10 | Access denied |
| 20 | Network failure |

Use `Exit-Success`, `Exit-Failure`, `Exit-NotApplicable`, `Exit-RebootRequired` from the toolkit.

## Software Detection

**Never use Win32_Product** -- it triggers MSI reconfiguration on every query, is slow, and can
cause side effects.

### Registry-Based Detection

```powershell
# Using toolkit function
$chrome = Test-SoftwareInstalled -Name '*Google Chrome*'
if ($chrome) {
    Write-Log "Found: $($chrome[0].DisplayName) v$($chrome[0].DisplayVersion)"
}

# Manual registry check (both 64-bit and 32-bit)
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$app = Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*MyApp*' }
```

## System Requirements Validation

Check prerequisites before running main logic:

```powershell
$reqs = Test-SystemRequirements -MinPSVersion 5.1 -MinDiskSpaceGB 2 -RequireAdmin
if (-not $reqs.Passed) {
    Write-Log "Requirements not met: $($reqs.Details)" -Level ERROR
    Exit-NotApplicable $reqs.Details
}
```

## Logging

Use `Write-Log` from the toolkit. It writes to both stdout (Datto captures) and a log file
under `$env:ProgramData\CentraStage\Logs\`.

```powershell
Write-Log "Starting installation"
Write-Log "Download failed" -Level ERROR
Write-Log "Skipping optional step" -Level WARN
Write-LogSection "Phase 2: Configuration"
```

## Run-As-User Patterns

Components run as SYSTEM by default. For user-context operations (HKCU registry, user apps):

### CPAs.dll Method (Recommended for UI / toast notifications)

`CPAs.dll` (murrayju.ProcessExtensions) uses `CreateProcessAsUser` to directly inject a process into the user's interactive session. This is the method used by official Datto-authored components for toast notifications and any UI that must be visible to the user.

```powershell
# Detect logged-on user first
$explorerProcs = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue
foreach ($proc in $explorerProcs) {
    $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwner
    if ($owner.ReturnValue -eq 0 -and $owner.User) {
        $varUsername = $owner.User
        break
    }
}

# Launch in user session via CPAs.dll (with timeout to prevent freeze)
$cpasJob = $null
try {
    $cpasJob = Start-Job -ScriptBlock {
        param($dll, $vbs, $workDir)
        [Reflection.Assembly]::LoadFile($dll) | Out-Null
        return [murrayju.ProcessExtensions.ProcessExtensions]::StartProcessAsCurrentUser(
            "wscript.exe", "`"$vbs`"", $workDir, $false
        )
    } -ArgumentList "$PWD\CPAs.dll", $varVBS, $PWD.Path

    $completed = Wait-Job -Job $cpasJob -Timeout 10
    if (-not $completed) { Stop-Job -Job $cpasJob }
    $result = if ($completed) { Receive-Job -Job $cpasJob } else { $false }
} catch {
    $result = $false
} finally {
    if ($cpasJob) { Remove-Job -Job $cpasJob -Force -ErrorAction SilentlyContinue }
}
```

**VBS silent launcher pattern** — use a VBS wrapper to run PowerShell with no visible window (CPAs.dll cannot pass `-WindowStyle Hidden` reliably through cmd.exe):
```vbs
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File ""C:\path\to\script.ps1""", 0, False
```

CPAs.dll hash verification:  
SHA1: `8031C2F6CF762EB11DF00ED68E9BA8A5EDDDAD12`  
SHA256: `F0BFA2B80BA20A1087BB3977DF744D2F5050D6078EC080AA3CCD438CCB68B7B8`

### Scheduled Task Method (Non-UI work)

```powershell
$result = Invoke-AsLoggedOnUser -ScriptBlock {
    param($Setting)
    Set-ItemProperty "HKCU:\Software\MyApp" -Name "Config" -Value $Setting -Force
} -ArgumentList 'enabled'
```

### All-Users Registry Method

For applying settings to ALL user hives (including users not currently logged in):

```powershell
Invoke-UserRegistryAction -Target All -Action {
    param($HivePath, $UserInfo)
    $path = "$HivePath\SOFTWARE\MyApp"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name 'Configured' -Value 1 -Type DWord -Force
}
```

## UDF Writing

Write status info to Datto UDFs (User Defined Fields 1-30) for dashboard visibility:

```powershell
Set-DattoUDF -UDF 5 -Value "BitLocker: Enabled | TPM: 2.0"
Set-DattoUDFTimestamp -UDF 20 -Value "Last patched by component"
# Result: "2026-03-01 19:30 | Last patched by component"
```
