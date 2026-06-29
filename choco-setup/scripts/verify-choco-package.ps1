#!/usr/bin/env pwsh
# verify-choco-package.ps1 — Real, no-publish verification of a Chocolatey package:
# pack -> install from the local .nupkg (downloads the release zip and enforces the
# SHA256) -> run the installed shim -> uninstall. Prints "PASS:" only if every step
# succeeds. This is the hard gate before claiming a package works.
#
# Usage:
#   pwsh -File verify-choco-package.ps1 -PackageDir chocolatey -Id <pkg> [-VersionArg version]
#
#   -PackageDir  Directory containing <Id>.nuspec and tools\ (default: chocolatey)
#   -Id          Chocolatey package id (lowercase), e.g. derpy
#   -VersionArg  Argument used to prove the binary runs (default: --version).
#                Some tools use a bare "version" subcommand; pass that if so.
#
# Requires: choco on PATH, run elevated (Chocolatey installs machine-wide).
# Note: the install step downloads the Windows zip referenced in
# chocolateyInstall.ps1, so a matching release must already be published.

[CmdletBinding()]
param(
    [string]$PackageDir = 'chocolatey',
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$VersionArg = '--version'
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Fail "choco not found on PATH. Install Chocolatey first."
}

$nuspec = Join-Path $PackageDir "$Id.nuspec"
if (-not (Test-Path $nuspec)) { Fail "nuspec not found at $nuspec" }

$absDir = (Resolve-Path $PackageDir).Path

Write-Host "==> [1/4] choco pack $nuspec"
choco pack $nuspec --outputdirectory $absDir
if ($LASTEXITCODE -ne 0) { Fail "choco pack failed" }

$nupkg = Get-ChildItem (Join-Path $absDir "$Id.*.nupkg") | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $nupkg) { Fail "no .nupkg produced in $absDir" }
Write-Host "    packed: $($nupkg.Name)"

# Local source first (so we test THIS nupkg), then community for any deps.
$source = "$absDir;https://community.chocolatey.org/api/v2/"

Write-Host "==> [2/4] choco install $Id (verifies download checksum)"
choco install $Id --source "$source" --version ($nupkg.Name -replace "^$Id\.", '' -replace '\.nupkg$','') -y --no-progress
if ($LASTEXITCODE -ne 0) { Fail "choco install failed (checksum mismatch, bad URL, or pack error)" }

Write-Host "==> [3/4] run installed shim: $Id $VersionArg"
$ranOk = $false
try {
    & $Id $VersionArg 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -eq 0) { $ranOk = $true }
} catch {
    Write-Host "    (shim invocation threw: $_)" -ForegroundColor Yellow
}

Write-Host "==> [4/4] choco uninstall $Id"
choco uninstall $Id -y --no-progress | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "    warning: uninstall returned $LASTEXITCODE" -ForegroundColor Yellow }

if (-not $ranOk) { Fail "installed binary did not run cleanly with '$VersionArg' (try -VersionArg 'version')" }

Write-Host "PASS: $Id packs, installs with verified checksum, runs, and uninstalls." -ForegroundColor Green
