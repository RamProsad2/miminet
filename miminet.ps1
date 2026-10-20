<#
.SYNOPSIS
  Run the Miminet dev stack from Windows PowerShell. Forwards to ./miminet.sh
  inside WSL, so the commands are the same: up, down, logs, doctor, smoke, ...

.EXAMPLE
  .\miminet.ps1 up
  .\miminet.ps1 logs back

.NOTES
  Clone the repo inside WSL (\\wsl$\<distro>\home\<you>\...), not on C:\ —
  this script works from either location, but builds on /mnt/c are slow and
  break file permissions. See docs/LOCAL_SETUP.md.
#>
param(
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed. Run 'wsl --install' in an elevated PowerShell, reboot, then retry."
    exit 1
}

# WSL 2.5+ ships a kernel (6.6+) with openvswitch/netem as modules; older
# releases (kernel 5.15) cannot run the emulation.
$wslVersion = (wsl.exe --version 2>$null) -join "`n" -replace "`0", ""
if ($wslVersion -match "(\d+)\.(\d+)\.(\d+)") {
    $major = [int]$Matches[1]; $minor = [int]$Matches[2]
    if ($major -lt 2 -or ($major -eq 2 -and $minor -lt 5)) {
        Write-Warning "WSL $($Matches[0]) is too old for the emulation. Run 'wsl --update' and then 'wsl --shutdown'."
    }
}

# Path of this repo as seen from WSL.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($here -match '^\\\\wsl(\.localhost|\$)\\[^\\]+(\\.*)$') {
    $repo = $Matches[2] -replace '\\', '/'
} else {
    $repo = (wsl.exe wslpath -a ($here -replace '\\', '/')).Trim()
}

$quoted = @($Command) + $Rest | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }
wsl.exe --cd "$repo" -- bash -lc "./miminet.sh $($quoted -join ' ')"
exit $LASTEXITCODE
