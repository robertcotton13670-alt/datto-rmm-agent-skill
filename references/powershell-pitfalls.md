# PowerShell 5.1 Pitfalls for Datto RMM

Datto RMM endpoints run PowerShell 5.1 on Windows. These are the non-obvious gotchas.

## ASCII-Only Source Files

PowerShell 5.1 mangles non-ASCII characters depending on the system's code page.

**Rules:**
- No emoji in .ps1 files
- No em dashes, curly quotes, or typographic characters
- No Unicode arrows or symbols
- Use only printable ASCII (0x20-0x7E) plus standard newlines

**Bad:**
```powershell
Write-Host "Check passed ✅"           # emoji
Write-Host "Error — see log"           # em dash
Write-Host "It's working"              # curly apostrophe (looks like ASCII but isn't)
```

**Good:**
```powershell
Write-Host "Check passed [OK]"
Write-Host "Error -- see log"
Write-Host "It's working"              # straight ASCII apostrophe
```

**Detection:** Open the file in a hex editor or run:
```powershell
$bytes = [System.IO.File]::ReadAllBytes("script.ps1")
$nonAscii = $bytes | Where-Object { $_ -gt 127 }
if ($nonAscii) { Write-Warning "Non-ASCII bytes found at positions: ..." }
```

## ForEach-Object += Scoping

`ForEach-Object` runs in a child scope in the pipeline. The `+=` operator creates a NEW
local variable instead of modifying the parent.

**Broken:**
```powershell
$items = @()
Get-ChildItem | ForEach-Object { $items += $_.Name }
# $items is STILL empty after the pipeline!
```

**Fix 1: Use foreach statement (not cmdlet):**
```powershell
$items = @()
foreach ($file in Get-ChildItem) { $items += $file.Name }
```

**Fix 2: Use a Generic List:**
```powershell
$items = [System.Collections.Generic.List[string]]::new()
Get-ChildItem | ForEach-Object { $items.Add($_.Name) }
```

**Fix 3: Capture pipeline output:**
```powershell
$items = Get-ChildItem | ForEach-Object { $_.Name }
```

## Write-Output vs Write-Host in Monitors

- `Write-Output` goes to the success output stream (pipeline). Datto's monitor parser
  may not capture it, causing "no data" results.
- `Write-Host` goes directly to the host console. Datto captures this reliably.

**Rule:** Monitors MUST use `Write-Host` for ALL output. Components (Scripts/Applications)
can use `Write-Output` freely since Datto captures stdout for those categories.

## Common Encoding Issues

### BOM (Byte Order Mark)
- PowerShell ISE saves as UTF-8 with BOM by default. This is generally fine.
- VS Code saves as UTF-8 without BOM by default. Also fine for ASCII content.
- Problem: If you copy-paste from a web browser, invisible Unicode characters may sneak in
  (zero-width spaces, non-breaking spaces, smart quotes).

### String Comparison
```powershell
# These look identical but aren't if one has a non-breaking space:
"Program Files" -eq "Program Files"  # might be $false!
```

### Fix: Always save .ps1 files as ASCII or UTF-8 without BOM, and validate with the
validation script before deploying.

## Execution Policy

Datto RMM bypasses execution policy when running components. However:

- If your component calls `powershell.exe` to run a sub-script, the child process
  inherits the machine's execution policy.
- Fix: Use `-ExecutionPolicy Bypass` explicitly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "subscript.ps1"
```

Or set it in the script:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

## Running as SYSTEM vs User Context

Datto components run as **NT AUTHORITY\SYSTEM** by default.

### What SYSTEM Can Do
- Access HKLM registry
- Install/uninstall software
- Manage services
- Access all file system paths (except encrypted user files)

### What SYSTEM Cannot Do
- Access HKCU (SYSTEM has its own HKCU, not the user's)
- See user's desktop, taskbar, or notification area
- Access user's AppData, Documents, etc. (without explicit path)
- Run processes visible to the logged-in user

### Solutions
- **HKCU access:** Use `Invoke-UserRegistryAction` (toolkit) to mount user hives
- **User-visible processes:** Use `Invoke-AsLoggedOnUser` (toolkit) via scheduled task
- **User profile paths:** Use `Get-LoggedOnUser` to find the profile path, then access directly

### Common Trap: $env:USERPROFILE
Under SYSTEM, `$env:USERPROFILE` is `C:\Windows\system32\config\systemprofile`.
Never assume it points to a real user's profile.

```powershell
# Wrong:
$desktop = "$env:USERPROFILE\Desktop"

# Right:
$user = Get-LoggedOnUser
$desktop = "$($user.ProfilePath)\Desktop"
```
