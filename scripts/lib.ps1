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
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
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
    if (-not $child.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the allowed root: $RelativePath"
    }
    return $child
}

function Assert-ValidProductName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -notmatch '^[a-z][a-z0-9-]{0,61}[a-z0-9]$') {
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

    $text = Get-Content -LiteralPath $Source -Raw
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

    $commandName = if ($Name -eq 'git') { 'git.exe' } else { 'gh.exe' }
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

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

function Get-TreeContentMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $map = [ordered]@{}
    Get-ChildItem -LiteralPath $root -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    return $map
}
