[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Apply,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$systemRoot = Get-ProductSystemRoot
$productRoot = [System.IO.Path]::GetFullPath($Path)
$manifestPath = Join-Path $productRoot '.product-system.json'
$manifest = Read-JsonFile -Path $manifestPath
$currentVersion = (Get-Content -LiteralPath (Join-Path $systemRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$defaults = Read-JsonFile -Path (Join-Path $systemRoot 'config/defaults.json')

function Get-ManifestSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$DefaultValue
    )

    $property = $manifest.PSObject.Properties[$Name]
    if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return $property.Value
    }
    return $DefaultValue
}

$runner = [string](Get-ManifestSetting -Name 'runner' -DefaultValue $defaults.runner)
$nodeMajor = [int](Get-ManifestSetting -Name 'nodeMajor' -DefaultValue $defaults.nodeMajor)
$pythonMinor = [string](Get-ManifestSetting -Name 'pythonMinor' -DefaultValue $defaults.pythonMinor)
Assert-ValidRuntimeSettings -Runner $runner -NodeMajor $nodeMajor -PythonMinor $pythonMinor

$tokens = @{
    '{{SYSTEM_VERSION}}' = $currentVersion
    '{{PRODUCT_NAME}}' = [string]$manifest.name
    '{{DISPLAY_NAME}}' = [string]$manifest.displayName
    '{{PROFILE}}' = [string]$manifest.profile
    '{{VISIBILITY}}' = [string]$manifest.visibility
    '{{LICENSE}}' = [string]$manifest.license
    '{{GITHUB_OWNER}}' = [string]$manifest.githubOwner
    '{{PYTHON_PACKAGE}}' = [string]$manifest.pythonPackage
    '{{RUNNER}}' = $runner
    '{{NODE_MAJOR}}' = $nodeMajor.ToString()
    '{{PYTHON_MINOR}}' = $pythonMinor
    '{{COPYRIGHT_YEAR}}' = [DateTime]::UtcNow.Year.ToString()
    '__PACKAGE__' = [string]$manifest.pythonPackage
}

$drift = New-Object System.Collections.ArrayList
foreach ($entry in (Get-ManagedEntries -Profile ([string]$manifest.profile))) {
    if ([string]$entry.policy -ne 'managed') { continue }

    $source = Resolve-SafeChildPath -BasePath $systemRoot -RelativePath ([string]$entry.source)
    $relativeTarget = Expand-TemplateText -Text ([string]$entry.target) -Tokens $tokens
    $target = Resolve-SafeChildPath -BasePath $productRoot -RelativePath $relativeTarget
    $expected = Expand-TemplateText -Text (Get-Content -LiteralPath $source -Raw -Encoding UTF8) -Tokens $tokens
    $actual = if (Test-Path -LiteralPath $target -PathType Leaf) { Get-Content -LiteralPath $target -Raw -Encoding UTF8 } else { $null }

    if ($actual -ne $expected) {
        $status = if ($null -eq $actual) { 'missing' } else { 'changed' }
        $drift.Add([pscustomobject]@{ Path = $relativeTarget.Replace('\\', '/'); Status = $status }) | Out-Null
        if ($Apply -and $PSCmdlet.ShouldProcess($target, 'Replace managed file from current product-system template')) {
            Write-Utf8NoBom -Path $target -Content $expected
        }
    }
}

if ($Apply) {
    $versionProperty = $manifest.PSObject.Properties['systemVersion']
    if ($versionProperty) { $versionProperty.Value = $currentVersion }
    else { $manifest | Add-Member -NotePropertyName systemVersion -NotePropertyValue $currentVersion }
    foreach ($setting in @(
        @{ Name = 'runner'; Value = $runner },
        @{ Name = 'nodeMajor'; Value = $nodeMajor },
        @{ Name = 'pythonMinor'; Value = $pythonMinor }
    )) {
        $property = $manifest.PSObject.Properties[[string]$setting.Name]
        if ($property) { $property.Value = $setting.Value }
        else { $manifest | Add-Member -NotePropertyName ([string]$setting.Name) -NotePropertyValue $setting.Value }
    }
    Write-Utf8NoBom -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 6) + "`n")

    $audit = & (Join-Path $PSScriptRoot 'audit.ps1') -Path $productRoot -SkipRuntime -PassThru
    if (-not $audit.Valid) { throw 'Managed files were synchronized, but the product audit failed.' }
}

$result = [pscustomobject]@{
    Path = $productRoot
    ProductVersion = [string]$manifest.systemVersion
    SystemVersion = $currentVersion
    DriftCount = $drift.Count
    Applied = [bool]$Apply
    Drift = @($drift | ForEach-Object { $_ })
}

if ($PassThru) {
    Write-Output $result
    return
}

foreach ($item in $drift) { Write-Host ("DRIFT {0}: {1}" -f $item.Status, $item.Path) }
if ($Apply) { Write-Host ("PASS: synchronized {0} managed file(s)." -f $drift.Count) }
elseif ($drift.Count -eq 0) { Write-Host 'PASS: managed files are current.' }
else { Write-Host ("CHECK: {0} managed file(s) differ. Re-run with -Apply after review." -f $drift.Count) }
