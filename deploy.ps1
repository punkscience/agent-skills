#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploys agent skills, subagents and commands from every repo under the
    parent directory into each harness directory.

.DESCRIPTION
    Source of truth is the set of sibling repos next to this script:

        ~/.agents/
          private/   skills/ agents/ commands/
          public/    skills/ agents/ commands/
          deploy.ps1 (this file, shipped in each repo)

    Targets (~/.claude) are treated as disposable build output. Nothing is
    linked; everything is copied. Deleting a target destroys nothing.

.PARAMETER Check
    Report drift and exit without writing anything.

.PARAMETER Target
    Harness directories to deploy into. Defaults to ~/.claude.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string[]]$Target = @((Join-Path $HOME '.claude'))
)

$ErrorActionPreference = 'Stop'
$Components = @('skills', 'agents', 'commands')
$Root = Split-Path -Parent $PSScriptRoot

# Junctions and symlinks are why the originals got deleted. Never recurse into
# one: unlink it and leave whatever it pointed at alone.
function Remove-Entry([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) }
        else { [IO.File]::Delete($item.FullName) }
        return
    }
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -File |
            ForEach-Object { $_.Attributes = 'Normal' }
        [IO.Directory]::Delete($item.FullName, $true)
    }
    else { [IO.File]::Delete($item.FullName) }
}

# A harness dir nested under $Root would otherwise be discovered as a source
# repo and deploy its own output back over itself.
$targetPaths = $Target | ForEach-Object {
    (Get-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue)?.FullName ?? [IO.Path]::GetFullPath($_)
}

$repos = Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object { $targetPaths -notcontains $_.FullName } |
    Where-Object { $r = $_; $Components | Where-Object { Test-Path (Join-Path $r.FullName $_) } }

if (-not $repos) {
    throw "No source repos found under $Root. Expected sibling directories containing skills/, agents/ or commands/."
}

Write-Host "Source repos: $($repos.Name -join ', ')"

# Build name -> source path per component, refusing to guess on collisions.
$plan = @{}
$collisions = @()
foreach ($component in $Components) {
    $map = [ordered]@{}
    foreach ($repo in $repos) {
        $dir = Join-Path $repo.FullName $component
        if (-not (Test-Path $dir)) { continue }
        foreach ($entry in Get-ChildItem -LiteralPath $dir -Force) {
            if ($map.Contains($entry.Name)) {
                $collisions += "$component/$($entry.Name): in both '$($map[$entry.Name].Repo)' and '$($repo.Name)'"
            }
            else {
                $map[$entry.Name] = [pscustomobject]@{ Path = $entry.FullName; Repo = $repo.Name }
            }
        }
    }
    $plan[$component] = $map
}

if ($collisions) {
    throw "Name collisions between repos - resolve before deploying:`n  " + ($collisions -join "`n  ")
}

foreach ($component in $Components) {
    Write-Host ("  {0,-9} {1} entries" -f $component, $plan[$component].Count)
}

$drift = 0
foreach ($harness in $Target) {
    Write-Host "`nTarget: $harness"
    foreach ($component in $Components) {
        $map = $plan[$component]
        if ($map.Count -eq 0) { continue }

        $dest = Join-Path $harness $component
        $destItem = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue

        # A junction here is the old broken layout. Replace it with a real directory.
        if ($destItem -and ($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Write-Host "  $component/ is a link -> replacing with a real directory"
            $drift++
            if (-not $Check) { Remove-Entry $dest; New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        }
        elseif (-not $destItem) {
            $drift++
            if (-not $Check) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        }

        # If the target is still a link, whatever it points at is not our output
        # and must not be reported or treated as stale - only the link goes.
        $existing = @{}
        $isLink = $destItem -and ($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ((Test-Path $dest) -and -not $isLink) {
            Get-ChildItem -LiteralPath $dest -Force | ForEach-Object { $existing[$_.Name] = $_.FullName }
        }

        foreach ($name in $map.Keys) {
            $src = $map[$name].Path
            $dst = Join-Path $dest $name
            if ($existing.ContainsKey($name)) {
                if (-not $Check) { Remove-Entry $dst }
            }
            else {
                Write-Host "  + $component/$name  ($($map[$name].Repo))"
                $drift++
            }
            if (-not $Check) { Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force }
        }

        # Anything in the target that no source repo provides is stale output.
        foreach ($name in $existing.Keys) {
            if (-not $map.Contains($name)) {
                Write-Host "  - $component/$name  (not in any source repo)"
                $drift++
                if (-not $Check) { Remove-Entry $existing[$name] }
            }
        }
    }
}

if ($Check) {
    if ($drift -eq 0) { Write-Host "`nIn sync." } else { Write-Host "`n$drift difference(s). Run deploy.ps1 to apply." }
    exit ($drift -gt 0 ? 1 : 0)
}
Write-Host "`nDeployed."
