[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }

if (-not $node -or -not $npm) {
    throw 'Node.js and npm are required for the node profile.'
}

Push-Location $root
try {
    & $npm.Source ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
    & $npm.Source run verify
    if ($LASTEXITCODE -ne 0) { throw "npm run verify failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Write-Host 'PASS: node repository verification'
