---
name: datto-rmm-dev
description: "Build, review, and validate Datto RMM components and monitors using Nathan's DattoRMM-toolkit patterns. Covers Datto RMM component development, RMM component creation, RMM script automation, RMM monitor development, Datto component best practices, PowerShell RMM scripting, monitoring script creation, and deployment script patterns."
---

# Datto RMM Component Development

Build Datto RMM components and monitors using the DattoRMM-toolkit.

## Quick Start

### New Component (Script or Application)
1. Copy `assets/templates/component.ps1` to your working location
2. Fill in the synopsis, description, and environment variable docs
3. Paste needed toolkit functions from `datto-rmm-toolkit/DattoRMM-Toolkit.ps1`
4. Implement logic in the `try` block
5. Validate: `powershell -File scripts/validate-component.ps1 -Path "your-script.ps1" -Type Component`

### New Monitor
1. Copy `assets/templates/monitor.ps1` to your working location
2. Fill in the synopsis and output variable docs
3. Implement check logic -- use Write-Host only, never Write-Output
4. Ensure the monitor output contract is followed (see below)
5. Validate: `powershell -File scripts/validate-component.ps1 -Path "your-monitor.ps1" -Type Monitor`

## Component Types

| Type | Timeout | Exit Codes | Convertible | Use For |
|------|---------|------------|-------------|---------|
| Applications | 30 min | 0=success, 3010=reboot required, 1641=reboot initiated | To/from Scripts | Software installs, large deployments, multi-step provisioning |
| Scripts | Flexible | 0=success, 1=warnings, 2=errors | To/from Applications | Automation tasks, config changes, maintenance, cleanup |
| Monitors | <3 sec (target <200ms) | 0=healthy, non-zero=alert | **Immutable** | Health checks, compliance, status reporting |

All run as **NT AUTHORITY\SYSTEM** (elevated). All must be non-interactive (no UI prompts).

**Important:** Monitor category cannot be changed after creation. Applications and Scripts can be converted between each other. Monitors must be direct-deployment only -- no launchers that pull scripts from external sources.

## Monitor Output Contract

Monitors must emit diagnostic and result markers with exactly one `Status=` line:

```
<-Start Diagnostic->
... diagnostic info ...
<-End Diagnostic->
<-Start Result->
Status=OK: All checks passed
<-End Result->
```

**Critical rules:**
- Write-Host for ALL output (never Write-Output)
- Exactly one Status= line in result block
- No spaces around `=`
- Exit 0 = healthy, exit 1 = alert
- Embed all functions -- no dot-sourcing

Full details: `references/monitor-contract.md`

## Toolkit Functions

The DattoRMM-Toolkit provides these function categories:

| Category | Key Functions |
|----------|--------------|
| Logging | `Write-Log`, `Write-LogSection` |
| Exit codes | `Exit-Success`, `Exit-Failure`, `Exit-NotApplicable`, `Exit-RebootRequired` |
| UDF management | `Set-DattoUDF`, `Get-DattoUDF`, `Set-DattoUDFTimestamp` |
| Environment | `Get-RMMVariable` (with type conversion), `Get-DattoVariable`, `Test-DattoAgent` |
| User context | `Get-LoggedOnUser`, `Invoke-AsLoggedOnUser` |
| Registry | `Invoke-UserRegistryAction`, `Get-UserRegistryPaths` |
| Software | `Test-SoftwareInstalled` (registry-based, never Win32_Product) |
| Downloads | `Invoke-FileDownload` (TLS 1.2, retry, hash, Authenticode) |
| System | `Test-SystemRequirements` |
| Monitor output | `Write-MonitorDiagnostic`, `Write-MonitorAlert`, `Write-MonitorSuccess` |

Full signatures and examples: `references/function-reference.md`

**For components:** Paste needed functions from the toolkit into the top of your script.
**For monitors:** Embed only the lightweight functions you need. Keep monitors self-contained.

## Key Rules

1. **Pure ASCII in all .ps1 files.** No emoji, em dashes, curly quotes, or Unicode. PS 5.1 mangles non-ASCII depending on code page.

2. **Monitors: Write-Host only.** Write-Output goes to the pipeline and causes "no data" in Datto's parser. Components (Scripts/Applications) can use Write-Output.

3. **TLS 1.2 for downloads.** Add at the top of any component that makes web requests:
   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   ```

4. **Never use Win32_Product.** It triggers MSI reconfiguration, is slow, and causes side effects. Use `Test-SoftwareInstalled` or query the registry uninstall keys directly.

5. **Exit codes matter.** Exit 0 = success/healthy. Exit 1 = failure/alert. Use the toolkit's `Exit-*` functions for components, `Write-MonitorAlert`/`Write-MonitorSuccess` for monitors.

6. **File attachments** land in the working directory. Reference by filename only -- no absolute paths. Always validate existence before use. Prefer attachments for static installers; prefer downloads for "always latest" where vendor provides stable URLs.

7. **Environment variables** from Datto use `$env:VariableName`. Use `Get-RMMVariable` for type conversion. Validate required vars early. Use secure variables for sensitive values (URLs, API keys).

8. **SYSTEM context.** Components run as SYSTEM. `$env:USERPROFILE` points to systemprofile, not the user. Use `Get-LoggedOnUser` and `Invoke-AsLoggedOnUser` for user-context work. SYSTEM has no network identity -- map network drives with explicit credentials if needed.

9. **ForEach-Object += scoping.** Pipeline ForEach-Object creates a child scope -- `+=` doesn't modify the parent variable. Use `foreach` statement or Generic List instead.

10. **Large file downloads (>1GB).** Use BITS transfer instead of Invoke-WebRequest:
    ```powershell
    Start-BitsTransfer -Source $uri -Destination $outFile -Priority Foreground
    ```

11. **Proxy-aware downloads.** Add `-UseDefaultCredentials` for environments behind a proxy.

12. **Monitor Output Variable** can be customized (default: `Status`). The variable name in the result block must match the Output Variable setting configured in the Datto RMM monitor. No spaces around `=`.

More pitfalls: `references/powershell-pitfalls.md`

## Creating Components Workflow

1. **Determine type:** Application (install), Script (automation), or Monitor (check).
2. **Copy template:** `assets/templates/component.ps1` for Scripts/Applications.
3. **Define inputs:** Document environment variables in the header. Use `Get-RMMVariable` with types and defaults.
4. **Add toolkit functions:** Paste only what you need from `DattoRMM-Toolkit.ps1`.
5. **Implement logic** in the try/catch block:
   - Validate prerequisites with `Test-SystemRequirements`
   - Use `Write-Log` throughout for diagnostics
   - Handle errors with specific exit codes
6. **Handle file attachments:** If the component uses attached files, validate they exist.
7. **Set TLS 1.2** if any downloads are involved.
8. **Write UDFs** if the component should report status to the Datto dashboard.
9. **Test locally** (run as admin to simulate SYSTEM context).
10. **Validate:** Run `scripts/validate-component.ps1 -Path "script.ps1" -Type Component`.

## Creating Monitors Workflow

1. **Copy template:** `assets/templates/monitor.ps1`.
2. **Set the output variable** name in the header (default: `Status`). Must match Datto config.
3. **Embed functions:** Copy only `Get-RMMVariable`, `Write-MonitorDiagnostic`, `Write-MonitorAlert`, `Write-MonitorSuccess` into the script. Add others only if needed.
4. **Start diagnostic block:** First line of output must be `Write-Host '<-Start Diagnostic->'`.
5. **Implement checks:**
   - Use Write-Host for all diagnostic output
   - Keep execution under 200ms where possible (3s max recommended)
   - Minimize file I/O and network calls
   - Use registry queries, not WMI, for software checks
6. **Exit via helper functions:**
   - `Write-MonitorSuccess "OK: description"` for healthy state
   - `Write-MonitorAlert "CRITICAL: description"` for alert state
   - These close the markers and call exit automatically
7. **Handle edge cases:** No user logged in, service not installed, first run.
8. **Add a stopwatch** during development to verify performance.
9. **Validate:** Run `scripts/validate-component.ps1 -Path "monitor.ps1" -Type Monitor`.
10. **Test the output** matches the marker contract before deploying.

## Review Checklist

When reviewing an existing component or monitor:

- [ ] Pure ASCII (no Unicode characters in .ps1)
- [ ] No Win32_Product queries
- [ ] Proper exit codes (0 for success, non-zero for failure)
- [ ] Error handling (try/catch with meaningful messages)
- [ ] Environment variables validated early
- [ ] TLS 1.2 set if downloads present
- [ ] File attachments validated before use
- [ ] **Monitors only:** Write-Host exclusively (no Write-Output)
- [ ] **Monitors only:** Diagnostic and result markers present
- [ ] **Monitors only:** Single Status= line in result block
- [ ] **Monitors only:** Self-contained (no external dependencies)
- [ ] No hardcoded paths that vary between environments
- [ ] No interactive prompts or UI elements
- [ ] Runs correctly as SYSTEM (not assuming user context)

## Reference Files

Load these on demand -- do not read all at once:

- `references/monitor-contract.md` -- Full monitor output contract with markers, rules, helpers, and common mistakes
- `references/component-patterns.md` -- Download, attachment, env var, error handling, software detection, logging, and run-as-user patterns
- `references/function-reference.md` -- All toolkit function signatures, parameters, and examples
- `references/powershell-pitfalls.md` -- PS 5.1 gotchas: ASCII encoding, ForEach scoping, Write-Output vs Write-Host, SYSTEM context

## Validation

Run the validation script against any component before deployment:

```powershell
# Validate a monitor
powershell -File scripts/validate-component.ps1 -Path "my-monitor.ps1" -Type Monitor

# Validate a component (script or application)
powershell -File scripts/validate-component.ps1 -Path "my-script.ps1" -Type Component
```

Errors must be fixed. Warnings should be reviewed and addressed where applicable.
