[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$LibraryRoot = (Join-Path $env:USERPROFILE 'AI_Library'),
    [switch]$AddToUserPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$gitReleaseTag = 'v2.55.0.windows.3'
$gitVersion = '2.55.0.3'
$gitArchiveName = 'PortableGit-2.55.0.3-64-bit.7z.exe'
$gitArchiveSha256 = 'ab00566336b5472120f9a52d34f2e79c5406535792acb0548001ffd0bd090e5d'
$gitUrl = "https://github.com/git-for-windows/git/releases/download/$gitReleaseTag/$gitArchiveName"

$ghVersion = '2.96.0'
$ghArchiveName = "gh_${ghVersion}_windows_amd64.zip"
$ghUrl = "https://github.com/cli/cli/releases/download/v$ghVersion/$ghArchiveName"
$ghChecksumsUrl = "https://github.com/cli/cli/releases/download/v$ghVersion/gh_${ghVersion}_checksums.txt"

$toolsRoot = [System.IO.Path]::GetFullPath((Join-Path $LibraryRoot 'tools'))
$gitDestination = Join-Path $toolsRoot "git/$gitVersion"
$ghDestination = Join-Path $toolsRoot "gh/$ghVersion"
$binDirectory = Join-Path $toolsRoot 'bin'
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('github-tooling-' + [Guid]::NewGuid().ToString('N'))

if (-not $PSCmdlet.ShouldProcess($toolsRoot, "Install verified portable Git $gitVersion and GitHub CLI $ghVersion")) {
    return
}

$null = New-Item -ItemType Directory -Path $staging
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path -LiteralPath (Join-Path $gitDestination 'cmd/git.exe') -PathType Leaf)) {
        $gitArchive = Join-Path $staging $gitArchiveName
        Invoke-WebRequest -UseBasicParsing -Uri $gitUrl -OutFile $gitArchive
        $actualGitHash = (Get-FileHash -LiteralPath $gitArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualGitHash -ne $gitArchiveSha256) {
            throw "Git archive hash mismatch. Expected $gitArchiveSha256, got $actualGitHash"
        }
        $null = New-Item -ItemType Directory -Path $gitDestination -Force
        & $gitArchive -y ("-o{0}" -f $gitDestination)
        if ($LASTEXITCODE -ne 0) { throw "PortableGit extraction failed with exit code $LASTEXITCODE" }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $ghDestination 'bin/gh.exe') -PathType Leaf)) {
        $ghArchive = Join-Path $staging $ghArchiveName
        $ghChecksums = Join-Path $staging 'gh_checksums.txt'
        Invoke-WebRequest -UseBasicParsing -Uri $ghUrl -OutFile $ghArchive
        Invoke-WebRequest -UseBasicParsing -Uri $ghChecksumsUrl -OutFile $ghChecksums

        $checksumLine = Get-Content -LiteralPath $ghChecksums | Where-Object { $_ -match ([regex]::Escape($ghArchiveName) + '$') } | Select-Object -First 1
        if (-not $checksumLine -or $checksumLine -notmatch '^([0-9a-fA-F]{64})\s+') {
            throw "Could not find an official checksum for $ghArchiveName"
        }
        $expectedGhHash = $Matches[1].ToLowerInvariant()
        $actualGhHash = (Get-FileHash -LiteralPath $ghArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualGhHash -ne $expectedGhHash) {
            throw "GitHub CLI archive hash mismatch. Expected $expectedGhHash, got $actualGhHash"
        }

        $ghExtractRoot = Join-Path $staging 'gh-extracted'
        Expand-Archive -LiteralPath $ghArchive -DestinationPath $ghExtractRoot
        $ghBinary = Get-ChildItem -LiteralPath $ghExtractRoot -Filter 'gh.exe' -File -Recurse | Select-Object -First 1
        if (-not $ghBinary) {
            throw 'GitHub CLI archive layout was not recognized.'
        }
        $binaryParent = Split-Path -Parent $ghBinary.FullName
        $expanded = if ((Split-Path -Leaf $binaryParent) -eq 'bin') { Split-Path -Parent $binaryParent } else { $binaryParent }
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ghDestination) -Force
        Move-Item -LiteralPath $expanded -Destination $ghDestination
    }

    $gitExe = Join-Path $gitDestination 'cmd/git.exe'
    $ghExe = Join-Path $ghDestination 'bin/gh.exe'
    & $gitExe --version
    if ($LASTEXITCODE -ne 0) { throw 'Installed Git did not start.' }
    & $ghExe --version
    if ($LASTEXITCODE -ne 0) { throw 'Installed GitHub CLI did not start.' }

    $null = New-Item -ItemType Directory -Path $binDirectory -Force
    Write-Utf8NoBom -Path (Join-Path $binDirectory 'git.cmd') -Content ("@`"{0}`" %*`r`n" -f $gitExe)
    Write-Utf8NoBom -Path (Join-Path $binDirectory 'gh.cmd') -Content ("@`"{0}`" %*`r`n" -f $ghExe)
    Write-Utf8NoBom -Path (Join-Path $binDirectory 'git-lfs.cmd') -Content ("@`"{0}`" lfs %*`r`n" -f $gitExe)

    if ($AddToUserPath) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts -notcontains $binDirectory) {
            $newPath = (@($parts) + $binDirectory) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }
    }

    $manifest = [ordered]@{
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        git = [ordered]@{ version = $gitVersion; path = $gitExe; sha256 = $gitArchiveSha256; source = $gitUrl }
        gh = [ordered]@{ version = $ghVersion; path = $ghExe; source = $ghUrl; checksums = $ghChecksumsUrl }
        commandDirectory = $binDirectory
        userPathUpdated = [bool]$AddToUserPath
    }
    Write-Utf8NoBom -Path (Join-Path $toolsRoot 'github-tooling.json') -Content (($manifest | ConvertTo-Json -Depth 5) + "`n")

    Write-Host "PASS: Git $gitVersion and gh $ghVersion installed under $toolsRoot"
    if ($AddToUserPath) { Write-Host 'Open a new terminal or restart Codex to receive the updated user PATH.' }
}
finally {
    if (Test-Path -LiteralPath $staging -PathType Container) {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $stagingFull = [System.IO.Path]::GetFullPath($staging)
        if ($stagingFull.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $stagingFull).StartsWith('github-tooling-')) {
            Remove-Item -LiteralPath $stagingFull -Recurse -Force
        }
    }
}
