Set-StrictMode -Version Latest

$script:ProductSystemRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Get-ProductSystemRoot {
    return $script:ProductSystemRoot
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fullPath, $Content, $encoding)
}

function Resolve-SafeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Expected a relative child path, got: $RelativePath"
    }

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([char[]]@('\', '/'))
    $child = [System.IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $child.StartsWith($prefix, $comparison)) {
        throw "Path escapes the allowed root: $RelativePath"
    }
    return $child
}

function Assert-ValidProductName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -cnotmatch '^[a-z][a-z0-9-]{0,61}[a-z0-9]$') {
        throw "Product name must be 2-63 lowercase characters: letters, digits, and internal hyphens."
    }

    $reserved = @('con', 'prn', 'aux', 'nul', 'clock$', 'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9', 'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9')
    if ($reserved -contains $Name.ToLowerInvariant()) {
        throw "Product name is reserved on Windows: $Name"
    }
}

function Expand-TemplateText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $result = $Text
    foreach ($key in $Tokens.Keys) {
        $result = $result.Replace([string]$key, [string]$Tokens[$key])
    }
    return $result
}

function Copy-RenderedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $text = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
    $rendered = Expand-TemplateText -Text $text -Tokens $Tokens
    Write-Utf8NoBom -Path $Destination -Content $rendered
}

function Get-ManagedEntries {
    param([Parameter(Mandatory = $true)][ValidateSet('generic', 'node', 'python')][string]$Profile)

    $manifest = Read-JsonFile -Path (Join-Path $script:ProductSystemRoot 'config/managed-files.json')
    $entries = @()
    $entries += @($manifest.base)
    $profileEntries = $manifest.profiles.$Profile
    if ($null -eq $profileEntries) {
        throw "No managed-file profile found: $Profile"
    }
    $entries += @($profileEntries)
    return $entries
}

function Get-PortableTool {
    param([Parameter(Mandatory = $true)][ValidateSet('git', 'gh')][string]$Name)

    $commandNames = if ($Name -eq 'git') { @('git.exe', 'git') } else { @('gh.exe', 'gh') }
    foreach ($commandName in $commandNames) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }

    if ([System.IO.Path]::DirectorySeparatorChar -ne '\' -or [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return $null
    }

    $libraryRoot = Join-Path $env:USERPROFILE 'AI_Library\tools'
    $toolingManifestPath = Join-Path $libraryRoot 'github-tooling.json'
    if (Test-Path -LiteralPath $toolingManifestPath -PathType Leaf) {
        try {
            $toolingManifest = Read-JsonFile -Path $toolingManifestPath
            $manifestPath = if ($Name -eq 'git') { [string]$toolingManifest.git.path } else { [string]$toolingManifest.gh.path }
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { return $manifestPath }
        }
        catch {
            # Fall through to version-directory discovery.
        }
    }

    $candidatePatterns = if ($Name -eq 'git') {
        @(
            (Join-Path $libraryRoot 'git/current/cmd/git.exe'),
            (Join-Path $libraryRoot 'git/*/cmd/git.exe')
        )
    }
    else {
        @(
            (Join-Path $libraryRoot 'gh/current/bin/gh.exe'),
            (Join-Path $libraryRoot 'gh/*/bin/gh.exe')
        )
    }

    foreach ($pattern in $candidatePatterns) {
        $candidate = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Assert-GitMainBranch {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    $branchOutput = & $Git -C $RepositoryPath symbolic-ref --quiet --short HEAD 2>$null
    $branchExitCode = $LASTEXITCODE
    if ($branchExitCode -ne 0) {
        throw 'Publishing requires an attached main branch; detached HEAD is not allowed.'
    }

    $branch = ($branchOutput | Out-String).Trim()
    if ($branch -ne 'main') {
        throw "Publishing requires branch main; current branch is $branch."
    }
}

function Assert-CleanGitWorktree {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    $null = & $Git -C $RepositoryPath rev-parse --verify HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Publishing requires at least one commit on main.'
    }

    $statusLines = @(& $Git -C $RepositoryPath status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not inspect the Git working tree before publishing.'
    }

    $changes = @($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($changes.Count -gt 0) {
        $preview = ($changes | Select-Object -First 10) -join '; '
        throw "Working tree is not clean. Commit or stash every audited change before publishing. Changes: $preview"
    }
}

function Resolve-PublishOwner {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestOwner,
        [AllowEmptyString()][string]$RequestedOwner
    )

    $manifestValue = $ManifestOwner.Trim()
    if ([string]::IsNullOrWhiteSpace($manifestValue)) {
        throw 'Product manifest does not define githubOwner.'
    }

    if ([string]::IsNullOrWhiteSpace($RequestedOwner)) {
        return $manifestValue
    }

    $requestedValue = $RequestedOwner.Trim()
    if ($requestedValue -ne $manifestValue) {
        throw "Owner mismatch: manifest=$manifestValue, requested=$requestedValue. Bootstrap the product for the intended owner before publishing."
    }
    return $manifestValue
}

function Assert-ValidRuntimeSettings {
    param(
        [Parameter(Mandatory = $true)][string]$Runner,
        [Parameter(Mandatory = $true)][int]$NodeMajor,
        [Parameter(Mandatory = $true)][string]$PythonMinor
    )

    if ($Runner -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Invalid runner label: $Runner"
    }
    if ($NodeMajor -lt 20 -or $NodeMajor -gt 99) {
        throw "Invalid Node major version: $NodeMajor"
    }

    $pythonVersion = $null
    if (-not [Version]::TryParse($PythonMinor, [ref]$pythonVersion) -or $pythonVersion.Major -ne 3 -or $pythonVersion.Minor -lt 10) {
        throw "Invalid Python minor version: $PythonMinor. Expected Python 3.10 or newer."
    }
}

function Get-TreeContentMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $map = [ordered]@{}
    Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    return $map
}
