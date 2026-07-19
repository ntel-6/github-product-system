[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$required = @(
    '.product-system.json',
    'README.md',
    '.github/workflows/ci.yml'
)

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $relative"
    }
}

$manifestPath = Join-Path $root '.product-system.json'
$null = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$unresolved = Get-ChildItem -LiteralPath $root -File -Recurse -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    Select-String -Pattern '\{\{[A-Z0-9_]+\}\}' -List

if ($unresolved) {
    throw "Unresolved template token found in $($unresolved[0].Path)"
}

Write-Host 'PASS: generic repository verification'
