#Requires -Version 5.1
<#
.SYNOPSIS
    Validate a Datto RMM component script for common issues.
.PARAMETER Path
    Path to the .ps1 file to validate.
.PARAMETER Type
    Component type: Monitor or Component.
.EXAMPLE
    .\validate-component.ps1 -Path "my-monitor.ps1" -Type Monitor
    .\validate-component.ps1 -Path "my-script.ps1" -Type Component
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidateSet('Monitor', 'Component')]
    [string]$Type
)

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

$content = Get-Content -Path $Path -Raw
$lines = Get-Content -Path $Path
$errors = 0
$warnings = 0

function Write-Issue {
    param([string]$Severity, [string]$Message)
    if ($Severity -eq 'ERROR') {
        Write-Host "  ERROR: $Message" -ForegroundColor Red
        $script:errors++
    }
    else {
        Write-Host "  WARN:  $Message" -ForegroundColor Yellow
        $script:warnings++
    }
}

Write-Host "Validating: $Path (Type: $Type)" -ForegroundColor Cyan
Write-Host ("-" * 60)

# Check for non-ASCII characters
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))
$nonAscii = @()
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -gt 127) { $nonAscii += $i }
}
if ($nonAscii.Count -gt 0) {
    Write-Issue 'WARN' "Non-ASCII bytes found at $($nonAscii.Count) position(s). First at byte offset $($nonAscii[0])."
}

# Check for Win32_Product (always an error)
if ($content -match 'Win32_Product') {
    Write-Issue 'ERROR' "Win32_Product detected. Use registry-based detection (Test-SoftwareInstalled) instead."
}

# Monitor-specific checks
if ($Type -eq 'Monitor') {
    # Check for Write-Output usage
    $writeOutputLines = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -match '^\s*Write-Output\b' -and $line -notmatch '^\s*#') {
            $writeOutputLines += ($i + 1)
        }
    }
    if ($writeOutputLines.Count -gt 0) {
        Write-Issue 'ERROR' "Write-Output found on line(s): $($writeOutputLines -join ', '). Monitors must use Write-Host exclusively."
    }

    # Check for diagnostic markers
    if ($content -notmatch '<-Start Diagnostic->') {
        Write-Issue 'ERROR' "Missing '<-Start Diagnostic->' marker."
    }
    if ($content -notmatch '<-End Diagnostic->') {
        Write-Issue 'ERROR' "Missing '<-End Diagnostic->' marker."
    }
    if ($content -notmatch '<-Start Result->') {
        Write-Issue 'ERROR' "Missing '<-Start Result->' marker."
    }
    if ($content -notmatch '<-End Result->') {
        Write-Issue 'ERROR' "Missing '<-End Result->' marker."
    }

    # Check for Status= line
    if ($content -notmatch 'Status=') {
        Write-Issue 'ERROR' "Missing 'Status=' result line inside result markers."
    }
}

# Check for TLS 1.2 enforcement in scripts with download patterns
if ($content -match 'Invoke-WebRequest|Invoke-RestMethod|WebClient|DownloadFile|DownloadString|Start-BitsTransfer') {
    if ($content -notmatch 'SecurityProtocol.*Tls12|Tls12.*SecurityProtocol') {
        Write-Issue 'WARN' "Download detected but TLS 1.2 not enforced. Add: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
    }
}

# Check for exit codes
if ($content -notmatch '\bexit\b|Exit-Component|Exit-Success|Exit-Failure|Write-MonitorAlert|Write-MonitorSuccess') {
    Write-Issue 'WARN' "No exit statement found. Components should explicitly exit with a code."
}

# Summary
Write-Host ("-" * 60)
if ($errors -eq 0 -and $warnings -eq 0) {
    Write-Host "PASSED: No issues found." -ForegroundColor Green
}
else {
    Write-Host "Result: $errors error(s), $warnings warning(s)" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Yellow' })
}

exit $(if ($errors -gt 0) { 1 } else { 0 })
