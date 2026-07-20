[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$DisplayName,
    [ValidateSet('generic', 'node', 'python')][string]$Profile = 'generic',
    [string]$Destination,
    [ValidateSet('private', 'public')][string]$Visibility,
    [ValidateSet('none', 'MIT', 'Apache-2.0')][string]$License,
    [string]$GithubOwner,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$Runner,
    [ValidateRange(20, 99)][int]$NodeMajor,
    [ValidatePattern('^[0-9]+\.[0-9]+$')][string]$PythonMinor,
    [switch]$InitGit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$systemRoot = Get-ProductSystemRoot
$defaults = Read-JsonFile -Path (Join-Path $systemRoot 'config/defaults.json')
$systemVersion = (Get-Content -LiteralPath (Join-Path $systemRoot 'VERSION') -Raw -Encoding UTF8).Trim()

Assert-ValidProductName -Name $Name

if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $Name }
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $defaultDestination = [string]$defaults.destination
    if ([string]::IsNullOrWhiteSpace($defaultDestination)) { throw 'defaults.destination must not be empty.' }
    $Destination = if ([System.IO.Path]::IsPathRooted($defaultDestination)) {
        $defaultDestination
    }
    else {
        Join-Path $systemRoot $defaultDestination
    }
}
if (-not $PSBoundParameters.ContainsKey('Visibility')) { $Visibility = [string]$defaults.visibility }
if (-not $PSBoundParameters.ContainsKey('License')) { $License = [string]$defaults.license }
if ([string]::IsNullOrWhiteSpace($GithubOwner)) { $GithubOwner = [string]$defaults.githubOwner }
if ([string]::IsNullOrWhiteSpace($Runner)) { $Runner = [string]$defaults.runner }
if (-not $PSBoundParameters.ContainsKey('NodeMajor')) { $NodeMajor = [int]$defaults.nodeMajor }
if ([string]::IsNullOrWhiteSpace($PythonMinor)) { $PythonMinor = [string]$defaults.pythonMinor }

if (@('private', 'public') -notcontains $Visibility) { throw "Unsupported default visibility: $Visibility" }
if (@('none', 'MIT', 'Apache-2.0') -notcontains $License) { throw "Unsupported default license: $License" }
Assert-ValidRuntimeSettings -Runner $Runner -NodeMajor $NodeMajor -PythonMinor $PythonMinor
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
    '{{RUNNER}}' = $Runner
    '{{NODE_MAJOR}}' = $NodeMajor.ToString()
    '{{PYTHON_MINOR}}' = $PythonMinor
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
        Runner = $Runner
        NodeMajor = $NodeMajor
        PythonMinor = $PythonMinor
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
