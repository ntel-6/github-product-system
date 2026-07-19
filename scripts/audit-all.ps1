[CmdletBinding()]
param(
    [string]$Root,
    [ValidateSet('Text', 'Json')][string]$Format = 'Text',
    [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent (Get-ProductSystemRoot) }

$rootPath = [System.IO.Path]::GetFullPath($Root)
$products = @(Get-ChildItem -LiteralPath $rootPath -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName '.product-system.json') -PathType Leaf
})

$results = @()
foreach ($product in $products) {
    $results += & (Join-Path $PSScriptRoot 'audit.ps1') -Path $product.FullName -SkipRuntime:$SkipRuntime -PassThru
}

$summary = [pscustomobject]@{
    Root = $rootPath
    Products = $results.Count
    Passing = @($results | Where-Object { $_.Valid }).Count
    Failing = @($results | Where-Object { -not $_.Valid }).Count
    Results = $results
}

if ($Format -eq 'Json') {
    $summary | ConvertTo-Json -Depth 7
}
else {
    foreach ($result in $results) {
        $status = if ($result.Valid) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0,-4} {1} [{2}] warnings={3} failures={4}" -f $status, $result.Path, $result.Profile, $result.Warn, $result.Fail)
    }
    Write-Host ("PORTFOLIO products={0} passing={1} failing={2}" -f $summary.Products, $summary.Passing, $summary.Failing)
}

if ($summary.Failing -gt 0) { exit 1 }
