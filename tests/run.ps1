[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$systemRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $systemRoot 'scripts/lib.ps1')
. (Join-Path $PSScriptRoot 'assert.ps1')

$tempName = '_tmp-' + [Guid]::NewGuid().ToString('N')
$tempRoot = Join-Path $PSScriptRoot $tempName
$null = New-Item -ItemType Directory -Path $tempRoot

try {
    $profiles = @('generic', 'node', 'python')
    foreach ($profile in $profiles) {
        $productName = "sample-$profile"
        $firstRoot = Join-Path $tempRoot "set-one-$profile"
        $secondRoot = Join-Path $tempRoot "set-two-$profile"
        $null = New-Item -ItemType Directory -Path $firstRoot
        $null = New-Item -ItemType Directory -Path $secondRoot
        $first = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name $productName -DisplayName "Sample $profile" -Profile $profile -Destination $firstRoot
        $second = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name $productName -DisplayName "Sample $profile" -Profile $profile -Destination $secondRoot

        $audit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $first.Path -SkipRuntime -PassThru
        Assert-True $audit.Valid "$profile profile must pass static audit"

        $firstMap = Get-TreeContentMap -Path $first.Path
        $secondMap = Get-TreeContentMap -Path $second.Path
        Assert-Equal $firstMap.Count $secondMap.Count "$profile generation file count"
        foreach ($key in $firstMap.Keys) {
            $comparisonKey = $key
            Assert-True $secondMap.Contains($comparisonKey) "$profile repeated output contains $comparisonKey"
            Assert-Equal $firstMap[$comparisonKey] $secondMap[$comparisonKey] "$profile deterministic file $comparisonKey"
        }

        $before = (Get-TreeContentMap -Path $first.Path | ConvertTo-Json -Compress)
        $runtimeAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $first.Path -PassThru
        Assert-True $runtimeAudit.Valid "$profile runtime audit must pass"
        $after = (Get-TreeContentMap -Path $first.Path | ConvertTo-Json -Compress)
        Assert-Equal $before $after "$profile audit must not mutate product"
    }

    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name '..\escape' -Destination $tempRoot } 'path traversal name'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name '../escape' -Destination $tempRoot } 'POSIX path traversal name'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'Uppercase' -Destination $tempRoot } 'uppercase product name'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'CON' -Destination $tempRoot } 'Windows reserved name'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'public-no-license' -Destination $tempRoot -Visibility public } 'public product without license'

    foreach ($licenseName in @('MIT', 'Apache-2.0')) {
        $licenseSlug = ('public-' + $licenseName.ToLowerInvariant().Replace('.', '-'))
        $licensed = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name $licenseSlug -Profile generic -Destination $tempRoot -Visibility public -License $licenseName
        $licensedAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $licensed.Path -SkipRuntime -PassThru
        Assert-True $licensedAudit.Valid "public $licenseName product must pass audit"
        Assert-True (Test-Path -LiteralPath (Join-Path $licensed.Path 'LICENSE') -PathType Leaf) "public $licenseName product has LICENSE"
    }

    $occupied = Join-Path $tempRoot 'occupied-product'
    $null = New-Item -ItemType Directory -Path $occupied
    Write-Utf8NoBom -Path (Join-Path $occupied 'keep.txt') -Content 'keep'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'occupied-product' -Destination $tempRoot } 'existing target'
    Assert-True (Test-Path -LiteralPath (Join-Path $occupied 'keep.txt')) 'existing target content must survive'

    $broken = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'broken-product' -Profile generic -Destination $tempRoot
    Remove-Item -LiteralPath (Join-Path $broken.Path 'README.md')
    $brokenAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $broken.Path -SkipRuntime -PassThru
    Assert-False $brokenAudit.Valid 'missing required file must fail audit'

    $secret = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'secret-product' -Profile generic -Destination $tempRoot
    Write-Utf8NoBom -Path (Join-Path $secret.Path '.env') -Content 'TOKEN=example'
    $secretAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $secret.Path -SkipRuntime -PassThru
    Assert-False $secretAudit.Valid 'secret-like file must fail audit'

    $unpinned = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'unpinned-action' -Profile generic -Destination $tempRoot
    $workflow = Join-Path $unpinned.Path '.github/workflows/ci.yml'
    $workflowText = (Get-Content -LiteralPath $workflow -Raw).Replace('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683', 'actions/checkout@v4')
    Write-Utf8NoBom -Path $workflow -Content $workflowText
    $unpinnedAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $unpinned.Path -SkipRuntime -PassThru
    Assert-False $unpinnedAudit.Valid 'unpinned action must fail audit'

    $syncProduct = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'sync-product' -Profile generic -Destination $tempRoot
    $syncWorkflow = Join-Path $syncProduct.Path '.github/workflows/ci.yml'
    Write-Utf8NoBom -Path $syncWorkflow -Content "name: changed`n"
    $userReadme = Join-Path $syncProduct.Path 'README.md'
    Add-Content -LiteralPath $userReadme -Value "`nUser-owned note"
    $syncCheck = & (Join-Path $systemRoot 'scripts/sync.ps1') -Path $syncProduct.Path -PassThru
    Assert-True ($syncCheck.DriftCount -gt 0) 'sync check must report managed drift'
    $null = & (Join-Path $systemRoot 'scripts/sync.ps1') -Path $syncProduct.Path -Apply -Confirm:$false -PassThru
    $syncAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $syncProduct.Path -SkipRuntime -PassThru
    Assert-True $syncAudit.Valid 'synchronized product must pass audit'
    Assert-True ((Get-Content -LiteralPath $userReadme -Raw).Contains('User-owned note')) 'sync must preserve create-only README'

    Write-Host 'PASS: all GitHub Product System tests'
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $expectedParent = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
        $tempFull = [System.IO.Path]::GetFullPath($tempRoot)
        if ($tempFull.StartsWith($expectedParent, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $tempFull).StartsWith('_tmp-')) {
            Remove-Item -LiteralPath $tempFull -Recurse -Force
        }
    }
}
