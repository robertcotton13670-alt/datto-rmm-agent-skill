# Datto RMM Agent Skill

> An AI agent skill for building production-ready Datto RMM components and monitors. Works with [OpenClaw](https://github.com/openclaw), Codex, and Claude Code. Also useful as a human reference.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green)

## What is this?

This is a **skill** -- a structured knowledge pack that AI coding agents can read to understand how to build Datto RMM components correctly. It contains:

- 📋 Templates for components and monitors
- 📖 Reference docs covering the monitor output contract, component patterns, and toolkit functions
- ✅ A validation script to catch common mistakes before deployment
- 🧠 Encoded best practices from real-world MSP deployments

Drop it into your agent's skill directory, and it knows how to write Datto RMM scripts that actually work in production.

**Not using an AI agent?** The docs, templates, and references are equally useful for humans building Datto RMM components.

## Features

- **Component templates** -- Pre-built scaffolding for Scripts, Applications, and Monitors
- **Monitor output contract** -- The exact marker format Datto's parser expects
- **Toolkit function reference** -- Logging, exit codes, UDF management, user-context execution, software detection, downloads
- **Validation script** -- Catches Write-Output in monitors, missing markers, Win32_Product usage, non-ASCII characters, and more
- **PowerShell 5.1 pitfalls** -- ForEach-Object scoping, SYSTEM context gotchas, encoding traps
- **Component patterns** -- Download retry, hash validation, Authenticode checks, BITS transfers, proxy awareness

## Quick Start

### With an AI Agent

1. Copy this repo (or just the skill folder) into your agent's skills directory
2. The agent reads `SKILL.md` and the reference files as needed
3. Ask it to "create a Datto RMM monitor that checks disk space" -- it knows the rules

### As a Human Reference

1. Start with [Getting Started](docs/getting-started.md)
2. Use the [Component Guide](docs/component-guide.md) or [Monitor Guide](docs/monitor-guide.md)
3. Copy a template from `assets/templates/` and fill it in
4. Validate with `scripts/validate-component.ps1`

## Component Types

| Type | Timeout | Exit Codes | Convertible | Use For |
|------|---------|------------|-------------|---------|
| Applications | 30 min | 0=success, 3010=reboot required, 1641=reboot initiated | To/from Scripts | Software installs, large deployments |
| Scripts | Flexible | 0=success, 1=warnings, 2=errors | To/from Applications | Automation, config changes, maintenance |
| Monitors | <3 sec (target <200ms) | 0=healthy, non-zero=alert | **Immutable** | Health checks, compliance, status reporting |

All components run as **NT AUTHORITY\SYSTEM** (elevated, non-interactive).

> ⚠️ Monitor category cannot be changed after creation. Applications and Scripts can be converted between each other.

## Monitor Output Contract

Datto RMM Custom Monitors parse stdout for specific markers:

```
<-Start Diagnostic->
... diagnostic info (timestamps, checks performed, details) ...
<-End Diagnostic->
<-Start Result->
Status=OK: All checks passed
<-End Result->
```

**Critical rules:**
- `Write-Host` for ALL output (never `Write-Output`)
- Exactly one `Status=` line in the result block
- No spaces around `=`
- Exit 0 = healthy, exit 1 = alert
- Embed all functions -- no dot-sourcing

Full details: [references/monitor-contract.md](references/monitor-contract.md)

## Toolkit Functions

| Category | Key Functions | Description |
|----------|--------------|-------------|
| Logging | `Write-Log`, `Write-LogSection` | Structured logging to file + stdout |
| Exit codes | `Exit-Success`, `Exit-Failure`, `Exit-NotApplicable`, `Exit-RebootRequired` | Clean exits with proper codes |
| UDF management | `Set-DattoUDF`, `Get-DattoUDF`, `Set-DattoUDFTimestamp` | Read/write Datto dashboard fields |
| Environment | `Get-RMMVariable`, `Get-DattoVariable`, `Test-DattoAgent` | Variable access with type conversion |
| User context | `Get-LoggedOnUser`, `Invoke-AsLoggedOnUser` | Run code as the logged-in user |
| Registry | `Invoke-UserRegistryAction`, `Get-UserRegistryPaths` | Manipulate user hives from SYSTEM |
| Software | `Test-SoftwareInstalled` | Registry-based detection (never Win32_Product) |
| Downloads | `Invoke-FileDownload` | TLS 1.2, retry, hash, Authenticode |
| System | `Test-SystemRequirements` | Prerequisite validation |
| Monitor output | `Write-MonitorDiagnostic`, `Write-MonitorAlert`, `Write-MonitorSuccess` | Monitor marker helpers |

Full signatures and examples: [references/function-reference.md](references/function-reference.md)

## Templates

| Template | Path | Description |
|----------|------|-------------|
| Component | `assets/templates/component.ps1` | Scaffold for Scripts and Applications with logging, error handling, and toolkit functions |
| Monitor | `assets/templates/monitor.ps1` | Scaffold for Monitors with embedded helpers, diagnostic markers, and stopwatch |

## Validation

Catch common issues before deploying to Datto RMM:

```powershell
# Validate a monitor
.\scripts\validate-component.ps1 -Path "my-monitor.ps1" -Type Monitor

# Validate a component (script or application)
.\scripts\validate-component.ps1 -Path "my-script.ps1" -Type Component
```

The validator checks for:
- Non-ASCII characters in .ps1 files
- `Win32_Product` usage
- `Write-Output` in monitors
- Missing diagnostic/result markers
- Missing TLS 1.2 enforcement for downloads
- Missing exit statements

## Key Rules

1. **Pure ASCII in all .ps1 files** -- No emoji, em dashes, curly quotes, or Unicode
2. **Monitors: Write-Host only** -- Write-Output causes "no data" in Datto's parser
3. **TLS 1.2 for downloads** -- Older Windows defaults to TLS 1.0/1.1
4. **Never use Win32_Product** -- Triggers MSI reconfiguration, slow, causes side effects
5. **Exit codes matter** -- 0=success/healthy, non-zero=failure/alert
6. **File attachments** -- Reference by filename only, always validate existence
7. **SYSTEM context** -- `$env:USERPROFILE` points to systemprofile, not the user
8. **ForEach-Object += scoping** -- Pipeline ForEach creates child scope; use `foreach` statement instead

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Quick start for humans and AI agents |
| [Component Guide](docs/component-guide.md) | Complete guide to building Scripts and Applications |
| [Monitor Guide](docs/monitor-guide.md) | Complete guide to building Monitors |
| [Monitor Contract](references/monitor-contract.md) | The exact output format Datto expects |
| [Component Patterns](references/component-patterns.md) | Download, attachment, error handling patterns |
| [Function Reference](references/function-reference.md) | All toolkit function signatures and examples |
| [PowerShell Pitfalls](references/powershell-pitfalls.md) | PS 5.1 gotchas for Datto RMM |

## Related Projects

- **[DattoRMM-toolkit](https://github.com/ompster/DattoRMM-toolkit)** -- The PowerShell toolkit that provides the helper functions referenced throughout this skill

## License

[MIT](LICENSE) -- Copyright 2026 Nathan Ash

## Author

**Nathan Ash** -- [GitHub](https://github.com/ompster)
