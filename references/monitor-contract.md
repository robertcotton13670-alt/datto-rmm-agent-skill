# Monitor Output Contract

Datto RMM Custom Monitors parse stdout for specific markers. Follow this contract exactly.

## Marker Format

```
<-Start Diagnostic->
... diagnostic lines (troubleshooting info, timestamps, checks performed) ...
<-End Diagnostic->
<-Start Result->
Status=OK: All checks passed
<-End Result->
```

## Rules

1. **Write-Host only.** Never use Write-Output, Write-Verbose, or Write-Error in monitors.
   Write-Output goes to the pipeline and can produce "no data" in Datto's parser.
2. **Exactly one Status= line** inside the result block. No extra lines between result markers.
3. **No spaces around `=`** in the status line: `Status=OK` not `Status = OK`.
4. **Exit codes:** `exit 0` = healthy/OK, `exit 1` (or non-zero) = alert/failed.
5. **Output variable name** must match the Datto RMM monitor's configured Output Variable
   (default: `Status`). If you configure a different name, use that instead.

## Helper Functions

Embed these in every monitor. Do NOT dot-source external files -- monitors must be self-contained.

```powershell
function Write-MonitorDiagnostic {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-Host $Message
}

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

These functions close the diagnostic block and open/close the result block automatically.
Call `Write-MonitorAlert` or `Write-MonitorSuccess` to terminate the monitor -- they call `exit`.

## Minimal Monitor Skeleton

```powershell
Write-Host '<-Start Diagnostic->'
Write-Host "Monitor: My Check"
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    # ... perform checks ...
    Write-Host "Check result: healthy"
    Write-MonitorSuccess "OK: All checks passed"
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-MonitorAlert "CRITICAL: $($_.Exception.Message)"
}
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `Write-Output` | Replace with `Write-Host` |
| Multiple Status= lines | Ensure only one call to Write-MonitorAlert/Success |
| Missing `<-Start Diagnostic->` at top | Add as the first Write-Host call |
| Spaces around `=` in status | Use `Status=OK` not `Status = OK` |
| No exit code | Write-MonitorAlert/Success handle this; if manual, always `exit 0` or `exit 1` |
| Dot-sourcing external files | Embed functions directly -- monitors must be self-contained |
| Write-Error for alerts | Use Write-Host + Write-MonitorAlert instead |

## Performance Targets

- **Recommended:** <200ms execution time
- **Hard limit:** <3 seconds (official Datto documentation)
- **Direct deployment only** -- no launcher scripts that pull code from external sources
- Embed all required functions directly in the monitor script
- Use `[System.Diagnostics.Stopwatch]` to measure execution time during development
- Minimize file I/O, network calls, and WMI queries
- Embed only the functions you need
