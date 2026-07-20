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

        $generatedManifest = Read-JsonFile -Path (Join-Path $first.Path '.product-system.json')
        Assert-Equal '1.1.0' ([string]$generatedManifest.systemVersion) "$profile manifest system version"
        Assert-Equal 'ubuntu-latest' ([string]$generatedManifest.runner) "$profile default runner"
        Assert-Equal 24 ([int]$generatedManifest.nodeMajor) "$profile default Node major"
        Assert-Equal '3.13' ([string]$generatedManifest.pythonMinor) "$profile default Python minor"
        $generatedWorkflow = Get-Content -LiteralPath (Join-Path $first.Path '.github/workflows/ci.yml') -Raw -Encoding UTF8
        Assert-True $generatedWorkflow.Contains("runs-on: 'ubuntu-latest'") "$profile workflow uses configured runner"
        $sourceContributing = Get-Content -LiteralPath (Join-Path $systemRoot 'templates/core/CONTRIBUTING.md') -Raw -Encoding UTF8
        $generatedContributing = Get-Content -LiteralPath (Join-Path $first.Path 'CONTRIBUTING.md') -Raw -Encoding UTF8
        Assert-Equal $sourceContributing $generatedContributing "$profile preserves UTF-8 template text"
        if ($profile -eq 'node') {
            Assert-True $generatedWorkflow.Contains('actions/setup-node@820762786026740c76f36085b0efc47a31fe5020') 'node setup action is SHA-pinned'
            Assert-True $generatedWorkflow.Contains("node-version: '24'") 'node workflow uses configured major'
            Assert-True ((Get-Content -LiteralPath (Join-Path $first.Path 'scripts/verify.ps1') -Raw -Encoding UTF8).Contains('ci --no-audit --no-fund')) 'node verification installs locked dependencies'
            Assert-True ((Get-Content -LiteralPath (Join-Path $first.Path 'package.json') -Raw -Encoding UTF8).Contains('"node": ">=24"')) 'node engine uses configured major'
        }
        elseif ($profile -eq 'python') {
            Assert-True $generatedWorkflow.Contains('actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1') 'python setup action is SHA-pinned'
            Assert-True $generatedWorkflow.Contains("python-version: '3.13'") 'python workflow uses configured minor'
            Assert-True $generatedWorkflow.Contains('python -m pip install --disable-pip-version-check -e .') 'python workflow installs the package'
            Assert-True ((Get-Content -LiteralPath (Join-Path $first.Path 'pyproject.toml') -Raw -Encoding UTF8).Contains('requires-python = ">=3.13"')) 'python project uses configured minor'
        }

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
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'invalid-runner' -Destination $tempRoot -Runner 'ubuntu latest' } 'invalid runner label'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'invalid-node' -Destination $tempRoot -NodeMajor 19 } 'unsupported Node major'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'invalid-python' -Destination $tempRoot -PythonMinor '3.x' } 'invalid Python minor'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'python-two' -Destination $tempRoot -PythonMinor '2.7' } 'Python 2 is unsupported'
    Assert-Throws { & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'python-old' -Destination $tempRoot -PythonMinor '3.9' } 'Python older than 3.10 is unsupported'

    Assert-Equal 'ntel-6' (Resolve-PublishOwner -ManifestOwner 'ntel-6' -RequestedOwner '') 'publish owner defaults to manifest'
    Assert-Equal 'ntel-6' (Resolve-PublishOwner -ManifestOwner 'ntel-6' -RequestedOwner 'NTEL-6') 'publish owner comparison is case-insensitive'
    Assert-Throws { Resolve-PublishOwner -ManifestOwner 'ntel-6' -RequestedOwner 'different-owner' } 'publish owner mismatch'

    $publishScriptPath = Join-Path $systemRoot 'scripts/publish.ps1'
    $parserTokens = $null
    $parserErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($publishScriptPath, [ref]$parserTokens, [ref]$parserErrors)
    Assert-Equal 0 @($parserErrors).Count 'publish script parses cleanly'
    $publishScriptText = Get-Content -LiteralPath $publishScriptPath -Raw -Encoding UTF8
    Assert-True $publishScriptText.Contains('sha_pinning_required=true') 'publish enables GitHub Actions SHA pinning'
    Assert-True $publishScriptText.Contains('private-vulnerability-reporting') 'publish enables private vulnerability reporting for public repositories'
    Assert-True $publishScriptText.Contains('secret_scanning_push_protection') 'publish enables secret scanning push protection for public repositories'

    $gitTool = Get-PortableTool -Name git
    if ($gitTool) {
        $gitStateRoot = Join-Path $tempRoot 'git-publish-state'
        $null = New-Item -ItemType Directory -Path $gitStateRoot
        & $gitTool -C $gitStateRoot init -b main | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'initialize publish-state repository'
        & $gitTool -C $gitStateRoot config user.name 'Product System Test'
        & $gitTool -C $gitStateRoot config user.email 'product-system-test@example.invalid'
        & $gitTool -C $gitStateRoot config commit.gpgsign false
        Assert-GitMainBranch -Git $gitTool -RepositoryPath $gitStateRoot
        Assert-Throws { Assert-CleanGitWorktree -Git $gitTool -RepositoryPath $gitStateRoot } 'repository without HEAD is not publishable'

        $trackedFile = Join-Path $gitStateRoot 'tracked.txt'
        Write-Utf8NoBom -Path $trackedFile -Content 'initial'
        & $gitTool -C $gitStateRoot add --all
        & $gitTool -C $gitStateRoot commit -m 'initial' | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'create initial publish-state commit'
        Assert-CleanGitWorktree -Git $gitTool -RepositoryPath $gitStateRoot

        Write-Utf8NoBom -Path $trackedFile -Content 'changed'
        Assert-Throws { Assert-CleanGitWorktree -Git $gitTool -RepositoryPath $gitStateRoot } 'tracked changes block publication'
        & $gitTool -C $gitStateRoot restore --worktree --staged tracked.txt
        Assert-Equal 0 $LASTEXITCODE 'restore tracked publish-state file'

        Write-Utf8NoBom -Path (Join-Path $gitStateRoot 'untracked.txt') -Content 'untracked'
        Assert-Throws { Assert-CleanGitWorktree -Git $gitTool -RepositoryPath $gitStateRoot } 'untracked files block publication'
        & $gitTool -C $gitStateRoot add --all
        & $gitTool -C $gitStateRoot commit -m 'add untracked fixture' | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'commit untracked publish-state fixture'

        & $gitTool -C $gitStateRoot switch -c feature | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'create non-main publish-state branch'
        Assert-Throws { Assert-GitMainBranch -Git $gitTool -RepositoryPath $gitStateRoot } 'non-main branch blocks publication'
        & $gitTool -C $gitStateRoot switch --detach HEAD | Out-Null
        Assert-Equal 0 $LASTEXITCODE 'detach publish-state HEAD'
        Assert-Throws { Assert-GitMainBranch -Git $gitTool -RepositoryPath $gitStateRoot } 'detached HEAD blocks publication'
    }
    else {
        Write-Host 'SKIP: Git publish-state tests (Git not found)'
    }

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
    $workflowText = (Get-Content -LiteralPath $workflow -Raw -Encoding UTF8).Replace('actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0', 'actions/checkout@v7')
    Write-Utf8NoBom -Path $workflow -Content $workflowText
    $unpinnedAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $unpinned.Path -SkipRuntime -PassThru
    Assert-False $unpinnedAudit.Valid 'unpinned action must fail audit'

    $writeAll = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'write-all-action' -Profile generic -Destination $tempRoot
    $writeAllWorkflow = Join-Path $writeAll.Path '.github/workflows/ci.yml'
    $writeAllText = (Get-Content -LiteralPath $writeAllWorkflow -Raw -Encoding UTF8) -replace '(?m)^permissions:\s*\r?\n\s+contents:\s+read\s*$', 'permissions: write-all'
    Write-Utf8NoBom -Path $writeAllWorkflow -Content $writeAllText
    $writeAllAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $writeAll.Path -SkipRuntime -PassThru
    Assert-False $writeAllAudit.Valid 'write-all workflow permission must fail audit'
    Assert-True (@($writeAllAudit.Checks | Where-Object { $_.Message -like 'write-all permission is forbidden*' }).Count -gt 0) 'write-all audit failure is explicit'

    $invalidRuntimeManifest = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'invalid-runtime-manifest' -Profile generic -Destination $tempRoot
    $invalidRuntimeManifestPath = Join-Path $invalidRuntimeManifest.Path '.product-system.json'
    $invalidRuntimeData = Read-JsonFile -Path $invalidRuntimeManifestPath
    $invalidRuntimeData.runner = 'ubuntu latest'
    $invalidRuntimeData.nodeMajor = 19
    $invalidRuntimeData.pythonMinor = '2.7'
    Write-Utf8NoBom -Path $invalidRuntimeManifestPath -Content (($invalidRuntimeData | ConvertTo-Json -Depth 6) + "`n")
    $invalidRuntimeAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $invalidRuntimeManifest.Path -SkipRuntime -PassThru
    Assert-False $invalidRuntimeAudit.Valid 'invalid manifest runtime settings must fail audit'
    Assert-True (@($invalidRuntimeAudit.Checks | Where-Object { $_.Id -eq 'manifest.runtime' -and $_.Status -eq 'FAIL' }).Count -eq 1) 'runtime manifest failure is explicit'

    $customRuntime = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') `
        -Name 'custom-runtime' `
        -Profile node `
        -Destination $tempRoot `
        -Runner 'windows-latest' `
        -NodeMajor 22 `
        -PythonMinor '3.12'
    $customManifest = Read-JsonFile -Path (Join-Path $customRuntime.Path '.product-system.json')
    Assert-Equal 'windows-latest' ([string]$customManifest.runner) 'custom runner is stored in manifest'
    Assert-Equal 22 ([int]$customManifest.nodeMajor) 'custom Node major is stored in manifest'
    Assert-Equal '3.12' ([string]$customManifest.pythonMinor) 'custom Python minor is stored in manifest'
    $customWorkflow = Get-Content -LiteralPath (Join-Path $customRuntime.Path '.github/workflows/ci.yml') -Raw -Encoding UTF8
    Assert-True $customWorkflow.Contains("runs-on: 'windows-latest'") 'custom runner is rendered into workflow'
    Assert-True $customWorkflow.Contains("node-version: '22'") 'custom Node major is rendered into workflow'
    $customAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $customRuntime.Path -SkipRuntime -PassThru
    Assert-True $customAudit.Valid 'custom runtime product passes static audit'
    $null = & (Join-Path $systemRoot 'scripts/sync.ps1') -Path $customRuntime.Path -Apply -Confirm:$false -PassThru
    $customManifestAfterSync = Read-JsonFile -Path (Join-Path $customRuntime.Path '.product-system.json')
    Assert-Equal 'windows-latest' ([string]$customManifestAfterSync.runner) 'sync preserves custom runner'
    Assert-Equal 22 ([int]$customManifestAfterSync.nodeMajor) 'sync preserves custom Node major'
    Assert-Equal '3.12' ([string]$customManifestAfterSync.pythonMinor) 'sync preserves custom Python minor'

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
    Assert-True ((Get-Content -LiteralPath $userReadme -Raw -Encoding UTF8).Contains('User-owned note')) 'sync must preserve create-only README'

    $legacySync = & (Join-Path $systemRoot 'scripts/bootstrap.ps1') -Name 'legacy-sync' -Profile generic -Destination $tempRoot
    $legacyManifestPath = Join-Path $legacySync.Path '.product-system.json'
    $legacyManifest = Read-JsonFile -Path $legacyManifestPath
    $legacyManifest.PSObject.Properties.Remove('runner')
    $legacyManifest.PSObject.Properties.Remove('nodeMajor')
    $legacyManifest.PSObject.Properties.Remove('pythonMinor')
    Write-Utf8NoBom -Path $legacyManifestPath -Content (($legacyManifest | ConvertTo-Json -Depth 6) + "`n")
    $legacyAudit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $legacySync.Path -SkipRuntime -PassThru
    Assert-True $legacyAudit.Valid 'legacy manifest without runtime fields remains valid'
    $legacyCheck = & (Join-Path $systemRoot 'scripts/sync.ps1') -Path $legacySync.Path -PassThru
    Assert-Equal 0 $legacyCheck.DriftCount 'legacy manifest uses runtime defaults during sync check'
    $null = & (Join-Path $systemRoot 'scripts/sync.ps1') -Path $legacySync.Path -Apply -Confirm:$false -PassThru
    $upgradedManifest = Read-JsonFile -Path $legacyManifestPath
    Assert-Equal 'ubuntu-latest' ([string]$upgradedManifest.runner) 'sync upgrades legacy manifest runner'
    Assert-Equal 24 ([int]$upgradedManifest.nodeMajor) 'sync upgrades legacy manifest Node major'
    Assert-Equal '3.13' ([string]$upgradedManifest.pythonMinor) 'sync upgrades legacy manifest Python minor'

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

$global:LASTEXITCODE = 0
