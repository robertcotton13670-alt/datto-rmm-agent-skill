#Requires -Version 5.1
<#
.SYNOPSIS
    [Component Name] - Datto RMM Component

.DESCRIPTION
    [Describe what this component does]

.COMPONENT
    Category: Scripts | Applications
    Timeout: 10min (Scripts) | 15min (Applications)

.INPUTS
    Environment Variables:
    - $env:VariableName  [String]  Description (required/optional)

.NOTES
    Author: Nathan Ash
    Version: 1.0.0
#>

# Datto RMM copies attached files into the script's working directory.
# Reference attachments by filename (no absolute paths needed).

# TLS 1.2 for any web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region ========================= TOOLKIT =========================
# Paste required functions from DattoRMM-Toolkit.ps1 here.
# At minimum, include Write-Log, Exit-Component, and any functions you use.

$script:LogPath = "$env:ProgramData\CentraStage\Logs\component-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO',
        [string]$LogFile = $script:LogPath
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Error $Message }
        'WARN'  { Write-Warning $Message }
        'DEBUG' { Write-Verbose $Message -Verbose }
        default { Write-Output $entry }
    }
}

function Exit-Component {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ExitCode, [Parameter(Mandatory)][string]$Message)
    $level = if ($ExitCode -eq 0) { 'INFO' } else { 'ERROR' }
    Write-Log $Message -Level $level
    Write-Log "Exiting with code: $ExitCode"
    [Console]::Out.Flush()
    exit $ExitCode
}

function Exit-Success { param([string]$Message = 'Component completed successfully.') Exit-Component -ExitCode 0 -Message $Message }
function Exit-Failure { param([string]$Message = 'Component failed.', [int]$ExitCode = 1) Exit-Component -ExitCode $ExitCode -Message $Message }

function Get-RMMVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet('String', 'Integer', 'Boolean', 'Double', 'Array')][string]$Type = 'String',
        $Default = $null
    )
    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($envValue)) { return $Default }
    switch ($Type) {
        'Integer' { try { return [int]$envValue } catch { return $Default } }
        'Boolean' { return (@('true', '1', 'yes', 'on', 'enabled') -contains $envValue.Trim().ToLower()) }
        'Double'  { try { return [double]$envValue } catch { return $Default } }
        'Array'   { $items = $envValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }; if ($items) { return @($items) }; return $Default }
        default { return $envValue }
    }
}

#endregion

#region ========================= MAIN ============================

try {
    Write-Log "Starting [Component Name]..."

    # Read environment variables
    # $target = Get-RMMVariable -Name 'TargetPath' -Type String -Default 'C:\Temp'

    # TODO: Implement component logic here

    Exit-Success "Component completed successfully"
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level DEBUG
    Exit-Failure "Failed: $($_.Exception.Message)"
}

#endregion
