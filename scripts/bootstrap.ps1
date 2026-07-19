[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$DisplayName,
    [ValidateSet('generic', 'node', 'python')][string]$Profile = 'generic',
    [string]$Destination,
    [ValidateSet('private', 'public')][string]$Visibility = 'private',
    [ValidateSet('none', 'MIT', 'Apache-2.0')][string]$License = 'none',
    [string]$GithubOwner,
    [switch]$InitGit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$systemRoot = Get-ProductSystemRoot
$defaults = Read-JsonFile -Path (Join-Path $systemRoot 'config/defaults.json')
$systemVersion = (Get-Content -LiteralPath (Join-Path $systemRoot 'VERSION') -Raw).Trim()

Assert-ValidProductName -Name $Name

if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Name }
if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = Split-Path -Parent $systemRoot }
if ([string]::IsNullOrWhiteSpace($GithubOwner)) { $GithubOwner = [string]$defaults.githubOwner }
if ($Visibility -eq 'public' -and $License -eq 'none') {
    throw 'A public product requires an explicit license: MIT or Apache-2.0.'
}

$destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd([char[]]@('\', '/'))
if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
    throw "Destination root does not exist: $destinationRoot"
}

$target = Resolve-SafeChildPath -BasePath $destinationRoot -RelativePath $Name
if ([System.IO.Path]::GetDirectoryName($target).TrimEnd([char[]]@('\', '/')) -ne $destinationRoot) {
    throw 'The product must be a direct child of Destination.'
}
if (Test-Path -LiteralPath $target) {
    throw "Target already exists; bootstrap never overwrites it: $target"
}

$pythonPackage = $Name.Replace('-', '_')
$tokens = @{
    '{{SYSTEM_VERSION}}' = $systemVersion
    '{{PRODUCT_NAME}}' = $Name
    '{{DISPLAY_NAME}}' = $DisplayName
    '{{PROFILE}}' = $Profile
    '{{VISIBILITY}}' = $Visibility
    '{{LICENSE}}' = $License
    '{{GITHUB_OWNER}}' = $GithubOwner
    '{{PYTHON_PACKAGE}}' = $pythonPackage
    '{{COPYRIGHT_YEAR}}' = [DateTime]::UtcNow.Year.ToString()
    '__PACKAGE__' = $pythonPackage
}

$stagingName = '.github-product-system-' + [Guid]::NewGuid().ToString('N')
$staging = Resolve-SafeChildPath -BasePath $destinationRoot -RelativePath $stagingName
$stagingCreated = $false

try {
    $null = New-Item -ItemType Directory -Path $staging
    $stagingCreated = $true

    Copy-RenderedFile `
        -Source (Join-Path $systemRoot 'templates/core/.product-system.json.tpl') `
        -Destination (Join-Path $staging '.product-system.json') `
        -Tokens $tokens

    foreach ($entry in (Get-ManagedEntries -Profile $Profile)) {
        $source = Resolve-SafeChildPath -BasePath $systemRoot -RelativePath ([string]$entry.source)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Template source is missing: $($entry.source)"
        }

        $relativeTarget = Expand-TemplateText -Text ([string]$entry.target) -Tokens $tokens
        $destinationFile = Resolve-SafeChildPath -BasePath $staging -RelativePath $relativeTarget
        Copy-RenderedFile -Source $source -Destination $destinationFile -Tokens $tokens
    }

    if ($License -ne 'none') {
        $licenseSource = Resolve-SafeChildPath -BasePath $systemRoot -RelativePath ("templates/licenses/{0}.txt.tpl" -f $License)
        Copy-RenderedFile -Source $licenseSource -Destination (Join-Path $staging 'LICENSE') -Tokens $tokens
    }

    $audit = & (Join-Path $systemRoot 'scripts/audit.ps1') -Path $staging -SkipRuntime -PassThru
    if (-not $audit.Valid) {
        $messages = @($audit.Checks | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { $_.Message }) -join '; '
        throw "Generated product did not pass audit: $messages"
    }

    Move-Item -LiteralPath $staging -Destination $target
    $stagingCreated = $false

    $gitStatus = 'not requested'
    if ($InitGit) {
        $git = Get-PortableTool -Name git
        if ($git) {
            & $git -C $target init -b main
            if ($LASTEXITCODE -ne 0) { throw "git init failed with exit code $LASTEXITCODE" }
            $gitStatus = 'initialized'
        }
        else {
            $gitStatus = 'skipped: git not found'
        }
    }

    $result = [pscustomobject]@{
        Path = $target
        Name = $Name
        Profile = $Profile
        Visibility = $Visibility
        License = $License
        Audit = 'PASS'
        Git = $gitStatus
    }
    Write-Host ("PASS: created {0} [{1}] at {2}" -f $Name, $Profile, $target)
    Write-Output $result
}
catch {
    if ($stagingCreated -and (Test-Path -LiteralPath $staging)) {
        $expectedPrefix = $destinationRoot + [System.IO.Path]::DirectorySeparatorChar + '.github-product-system-'
        if ($staging.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
    throw
}
