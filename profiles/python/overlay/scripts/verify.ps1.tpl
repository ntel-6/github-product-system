[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$candidates = @('python3', 'py', 'python')
if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $candidates += Join-Path $env:USERPROFILE 'AI_Library\.venv\Scripts\python.exe'
}
$python = $null
$prefix = @()

foreach ($candidate in $candidates) {
    $candidatePython = $null
    $candidatePrefix = @()
    if ($candidate -eq 'py') {
        $command = Get-Command py -ErrorAction SilentlyContinue
        if ($command) { $candidatePython = $command.Source; $candidatePrefix = @('-3') }
    }
    elseif ([System.IO.Path]::IsPathRooted($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidatePython = $candidate }
    }
    else {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { $candidatePython = $command.Source }
    }

    if ($candidatePython) {
        $probe = $null
        $probeExitCode = 1
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            $probe = & $candidatePython @candidatePrefix -c "import sys; print(sys.version_info.major)" 2>$null
            $probeExitCode = $LASTEXITCODE
        }
        catch {
            $probeExitCode = 1
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($probeExitCode -eq 0 -and ($probe | Out-String).Trim() -eq '3') {
            $python = $candidatePython
            $prefix = $candidatePrefix
            break
        }
    }
}

if (-not $python) {
    throw 'Python 3 is required for the python profile.'
}

Push-Location $root
try {
    $previousBytecodeSetting = $env:PYTHONDONTWRITEBYTECODE
    $env:PYTHONDONTWRITEBYTECODE = '1'
    try {
        $syntaxCheck = "import ast,pathlib; files=list(pathlib.Path('src').rglob('*.py'))+list(pathlib.Path('tests').rglob('*.py')); [ast.parse(p.read_text(encoding='utf-8'), filename=str(p)) for p in files]"
        & $python @prefix -B -c $syntaxCheck
        if ($LASTEXITCODE -ne 0) { throw "Python syntax check failed with exit code $LASTEXITCODE" }
        & $python @prefix -B -m unittest discover -s tests -v
        if ($LASTEXITCODE -ne 0) { throw "unittest failed with exit code $LASTEXITCODE" }
    }
    finally {
        $env:PYTHONDONTWRITEBYTECODE = $previousBytecodeSetting
    }
}
finally {
    Pop-Location
}

Write-Host 'PASS: python repository verification'
