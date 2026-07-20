[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('Text', 'Json')][string]$Format = 'Text',
    [switch]$SkipRuntime,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$productRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
if (-not (Test-Path -LiteralPath $productRoot -PathType Container)) {
    throw "Product path does not exist: $productRoot"
}

$checks = New-Object System.Collections.ArrayList
function Add-Check {
    param([string]$Status, [string]$Id, [string]$Message)
    $checks.Add([pscustomobject]@{ Status = $Status; Id = $Id; Message = $Message }) | Out-Null
}

$baseline = Read-JsonFile -Path (Join-Path (Get-ProductSystemRoot) 'policy/baseline.json')
$defaults = Read-JsonFile -Path (Join-Path (Get-ProductSystemRoot) 'config/defaults.json')
$manifestPath = Join-Path $productRoot '.product-system.json'
$manifest = $null
try {
    $manifest = Read-JsonFile -Path $manifestPath
    Add-Check 'PASS' 'manifest.json' 'Product manifest is valid JSON.'
}
catch {
    Add-Check 'FAIL' 'manifest.json' $_.Exception.Message
}

if ($manifest) {
    $runnerProperty = $manifest.PSObject.Properties['runner']
    $nodeMajorProperty = $manifest.PSObject.Properties['nodeMajor']
    $pythonMinorProperty = $manifest.PSObject.Properties['pythonMinor']
    $manifestRunner = if ($runnerProperty) { [string]$runnerProperty.Value } else { [string]$defaults.runner }
    $manifestNodeMajorRaw = if ($nodeMajorProperty) { $nodeMajorProperty.Value } else { $defaults.nodeMajor }
    $manifestPythonMinor = if ($pythonMinorProperty) { [string]$pythonMinorProperty.Value } else { [string]$defaults.pythonMinor }
    try {
        $manifestNodeMajor = [int]$manifestNodeMajorRaw
        Assert-ValidRuntimeSettings -Runner $manifestRunner -NodeMajor $manifestNodeMajor -PythonMinor $manifestPythonMinor
        Add-Check 'PASS' 'manifest.runtime' "Runtime settings are valid: runner=$manifestRunner, node=$manifestNodeMajor, python=$manifestPythonMinor."
    }
    catch {
        Add-Check 'FAIL' 'manifest.runtime' $_.Exception.Message
    }

    if ([int]$manifest.schemaVersion -ne [int]$baseline.schemaVersion) {
        Add-Check 'FAIL' 'manifest.schema' "Unsupported schemaVersion: $($manifest.schemaVersion)"
    }
    elseif (@($baseline.allowedProfiles) -notcontains [string]$manifest.profile) {
        Add-Check 'FAIL' 'manifest.profile' "Unsupported profile: $($manifest.profile)"
    }
    else {
        Add-Check 'PASS' 'manifest.schema' "Schema and profile are supported: $($manifest.profile)."
    }

    $profileName = [string]$manifest.profile
    $profileProperty = $baseline.requiredByProfile.PSObject.Properties[$profileName]
    $profileRequired = if ($profileProperty) { @($profileProperty.Value) } else { @() }
    $required = @($baseline.requiredCore) + $profileRequired
    if ([string]$manifest.profile -eq 'python') {
        $required += "src/$($manifest.pythonPackage)/__init__.py"
    }
    foreach ($relative in $required) {
        $requiredPath = Resolve-SafeChildPath -BasePath $productRoot -RelativePath ([string]$relative)
        if (Test-Path -LiteralPath $requiredPath -PathType Leaf) {
            Add-Check 'PASS' 'required.file' "Present: $relative"
        }
        else {
            Add-Check 'FAIL' 'required.file' "Missing: $relative"
        }
    }

    if ([string]$manifest.visibility -eq 'public') {
        if ([string]$manifest.license -eq 'none' -or -not (Test-Path -LiteralPath (Join-Path $productRoot 'LICENSE') -PathType Leaf)) {
            Add-Check 'FAIL' 'public.license' 'Public products require an explicit LICENSE.'
        }
        else {
            Add-Check 'PASS' 'public.license' "Public license is $($manifest.license)."
        }
    }
}

$allFiles = @(Get-ChildItem -LiteralPath $productRoot -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })

foreach ($jsonFile in @($allFiles | Where-Object { $_.Extension -eq '.json' })) {
    try {
        $jsonText = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8
        if ($jsonFile.Name -eq 'package-lock.json') {
            # Windows PowerShell 5.1 rejects the valid empty property used by npm lockfiles.
            $jsonText = $jsonText -replace '(?m)^(\s*)"":', '$1"__package_root__":'
        }
        $null = $jsonText | ConvertFrom-Json
        Add-Check 'PASS' 'json.valid' "Valid JSON: $($jsonFile.Name)"
    }
    catch {
        Add-Check 'FAIL' 'json.valid' "Invalid JSON: $($jsonFile.FullName)"
    }
}

$textExtensions = @('.md', '.txt', '.json', '.yml', '.yaml', '.ps1', '.js', '.py', '.toml', '.gitignore', '.gitattributes', '.editorconfig')
foreach ($file in $allFiles) {
    $leaf = $file.Name.ToLowerInvariant()
    $extension = $file.Extension.ToLowerInvariant()

    if (@($baseline.blockedFileNames) -contains $leaf -or @($baseline.blockedExtensions) -contains $extension) {
        Add-Check 'FAIL' 'secret.file' "Blocked secret-like file: $($file.FullName)"
    }

    if ($file.Length -ge [long]$baseline.failFileSizeBytes) {
        Add-Check 'FAIL' 'file.size' "File is 50 MB or larger: $($file.FullName)"
    }
    elseif ($file.Length -ge [long]$baseline.warnFileSizeBytes) {
        Add-Check 'WARN' 'file.size' "File is 25 MB or larger: $($file.FullName)"
    }

    if ($textExtensions -contains $extension -or $leaf.StartsWith('.')) {
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($content -match '\{\{[A-Z0-9_]+\}\}' -or $content -match '__PACKAGE__') {
                Add-Check 'FAIL' 'template.token' "Unresolved template token: $($file.FullName)"
            }
        }
        catch {
            Add-Check 'WARN' 'text.read' "Could not inspect text file: $($file.FullName)"
        }
    }
}

$workflowRoot = Join-Path $productRoot '.github/workflows'
if (Test-Path -LiteralPath $workflowRoot -PathType Container) {
    foreach ($workflow in @(Get-ChildItem -LiteralPath $workflowRoot -File -Force | Where-Object { $_.Extension -in @('.yml', '.yaml') })) {
        $yaml = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding UTF8
        if ($yaml -match '(?m)^\s*pull_request_target\s*:') {
            Add-Check 'FAIL' 'workflow.trigger' "pull_request_target is forbidden: $($workflow.Name)"
        }
        if ($yaml -match '(?m)^\s*permissions\s*:\s*write-all\s*(?:#.*)?$') {
            Add-Check 'FAIL' 'workflow.permissions' "write-all permission is forbidden: $($workflow.Name)"
        }
        elseif ($yaml -notmatch '(?m)^permissions\s*:' -or $yaml -notmatch '(?m)^\s+contents\s*:\s*read\s*$') {
            Add-Check 'FAIL' 'workflow.permissions' "Workflow must declare contents: read: $($workflow.Name)"
        }
        elseif ($yaml -match '(?m)^\s+[a-z-]+\s*:\s*write\s*$') {
            Add-Check 'FAIL' 'workflow.permissions' "Write permission is not allowed in baseline CI: $($workflow.Name)"
        }
        else {
            Add-Check 'PASS' 'workflow.permissions' "Minimal permissions: $($workflow.Name)"
        }

        foreach ($needle in @('pull_request:', 'push:', 'timeout-minutes:', 'concurrency:', 'main')) {
            if (-not $yaml.Contains($needle)) {
                Add-Check 'FAIL' 'workflow.baseline' "Missing '$needle' in $($workflow.Name)"
            }
        }

        foreach ($line in ($yaml -split "`r?`n")) {
            if ($line -match '^\s*uses:\s*([^\s]+)') {
                $use = $Matches[1]
                if (-not $use.StartsWith('./')) {
                    $at = $use.LastIndexOf('@')
                    $reference = if ($at -ge 0) { $use.Substring($at + 1) } else { '' }
                    if ($reference -notmatch '^[0-9a-fA-F]{40}$') {
                        Add-Check 'FAIL' 'workflow.action-pin' "Action is not pinned to a full SHA: $use"
                    }
                }
            }
        }
    }
}

if ($manifest) {
    $dependabotPath = Join-Path $productRoot '.github/dependabot.yml'
    if (Test-Path -LiteralPath $dependabotPath -PathType Leaf) {
        $dependabot = Get-Content -LiteralPath $dependabotPath -Raw -Encoding UTF8
        if ($dependabot -notmatch 'package-ecosystem:\s*github-actions') {
            Add-Check 'FAIL' 'dependabot.actions' 'Dependabot must update GitHub Actions.'
        }
        $expectedEcosystem = if ([string]$manifest.profile -eq 'node') { 'npm' } elseif ([string]$manifest.profile -eq 'python') { 'pip' } else { $null }
        if ($expectedEcosystem -and $dependabot -notmatch ("package-ecosystem:\s*{0}" -f $expectedEcosystem)) {
            Add-Check 'FAIL' 'dependabot.profile' "Dependabot is missing ecosystem: $expectedEcosystem"
        }
    }
}

if ($SkipRuntime) {
    Add-Check 'SKIP' 'runtime.verify' 'Runtime verification was skipped by request.'
}
elseif (Test-Path -LiteralPath (Join-Path $productRoot 'scripts/verify.ps1') -PathType Leaf) {
    $engine = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile')
    if ($env:OS -eq 'Windows_NT') { $arguments += @('-ExecutionPolicy', 'Bypass') }
    $arguments += @('-File', (Join-Path $productRoot 'scripts/verify.ps1'))
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $runtimeOutput = & $engine @arguments 2>&1
        $runtimeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($runtimeExitCode -eq 0) {
        Add-Check 'PASS' 'runtime.verify' (($runtimeOutput | Out-String).Trim())
    }
    else {
        Add-Check 'FAIL' 'runtime.verify' (($runtimeOutput | Out-String).Trim())
    }
}

$failCount = @($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq 'WARN' }).Count
$passCount = @($checks | Where-Object { $_.Status -eq 'PASS' }).Count
$skipCount = @($checks | Where-Object { $_.Status -eq 'SKIP' }).Count
$result = [pscustomobject]@{
    Valid = ($failCount -eq 0)
    Path = $productRoot
    Profile = if ($manifest) { [string]$manifest.profile } else { $null }
    Pass = $passCount
    Warn = $warnCount
    Fail = $failCount
    Skip = $skipCount
    Checks = @($checks | ForEach-Object { $_ })
}

if ($PassThru) {
    Write-Output $result
    return
}

if ($Format -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    foreach ($check in $checks) {
        Write-Host ("{0,-4} {1}: {2}" -f $check.Status, $check.Id, $check.Message)
    }
    Write-Host ("RESULT PASS: {0}  WARN: {1}  FAIL: {2}  SKIP: {3}" -f $passCount, $warnCount, $failCount, $skipCount)
}

if (-not $result.Valid) { exit 1 }
