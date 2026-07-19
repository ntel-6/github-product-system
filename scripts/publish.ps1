[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Owner = 'ntel-6',
    [ValidateSet('private', 'public')][string]$Visibility = 'private',
    [switch]$TemplateRepository,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._/-]{0,99}$')][string]$RequiredCheck = 'verify'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib.ps1')

$productRoot = [System.IO.Path]::GetFullPath($Path)
$audit = & (Join-Path $PSScriptRoot 'audit.ps1') -Path $productRoot -PassThru
if (-not $audit.Valid) { throw 'Product audit failed; publication is blocked.' }

$manifest = Read-JsonFile -Path (Join-Path $productRoot '.product-system.json')
$slug = [string]$manifest.name
Assert-ValidProductName -Name $slug
$fullName = "$Owner/$slug"

if ([string]$manifest.visibility -ne $Visibility) {
    throw "Visibility mismatch: manifest=$($manifest.visibility), requested=$Visibility"
}

$git = Get-PortableTool -Name git
$gh = Get-PortableTool -Name gh
if (-not $git) { throw 'Git is not installed. Run scripts/install-tooling.ps1 first.' }
if (-not $gh) { throw 'GitHub CLI is not installed. Run scripts/install-tooling.ps1 first.' }

& $gh auth status --active --hostname github.com
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run gh auth login --web --git-protocol https.' }

$null = & $gh repo view $fullName --json nameWithOwner 2>$null
if ($LASTEXITCODE -eq 0) {
    throw "Remote repository already exists; publish refuses to guess how to merge: $fullName"
}

if (-not $PSCmdlet.ShouldProcess($fullName, "Create and push $Visibility GitHub repository")) {
    return
}

if (-not (Test-Path -LiteralPath (Join-Path $productRoot '.git') -PathType Container)) {
    & $git -C $productRoot init -b main
    if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
}

$gitName = (& $git -C $productRoot config user.name 2>$null | Out-String).Trim()
$gitEmail = (& $git -C $productRoot config user.email 2>$null | Out-String).Trim()
if (-not $gitName -or -not $gitEmail) {
    throw 'Git identity is missing. Configure verified user.name and user.email (or GitHub noreply email) before publishing.'
}

$null = & $git -C $productRoot rev-parse --verify HEAD 2>$null
if ($LASTEXITCODE -ne 0) {
    & $git -C $productRoot add --all
    if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
    & $git -C $productRoot commit -m "chore: initialize $slug"
    if ($LASTEXITCODE -ne 0) { throw 'Initial commit failed.' }
}

$visibilityFlag = if ($Visibility -eq 'public') { '--public' } else { '--private' }
& $gh repo create $fullName $visibilityFlag --source $productRoot --remote origin --push
if ($LASTEXITCODE -ne 0) { throw 'GitHub repository creation or push failed.' }

& $gh api --method PATCH "repos/$fullName" `
    -F has_issues=true `
    -F has_wiki=false `
    -F delete_branch_on_merge=true `
    -F allow_squash_merge=true `
    -F allow_merge_commit=false `
    -F allow_rebase_merge=false
if ($LASTEXITCODE -ne 0) { throw 'Repository settings update failed.' }

& $gh repo edit $fullName --add-topic product-system --add-topic ([string]$manifest.profile)
if ($LASTEXITCODE -ne 0) { throw 'Repository topic update failed.' }

$labels = @(
    @{ Name = 'bug'; Color = 'd73a4a'; Description = 'Reproducible defect' },
    @{ Name = 'enhancement'; Color = 'a2eeef'; Description = 'Product improvement' },
    @{ Name = 'triage'; Color = 'fbca04'; Description = 'Needs initial review' },
    @{ Name = 'security'; Color = 'b60205'; Description = 'Security work' },
    @{ Name = 'documentation'; Color = '0075ca'; Description = 'Documentation' },
    @{ Name = 'dependencies'; Color = '0366d6'; Description = 'Dependency update' }
)
foreach ($label in $labels) {
    & $gh label create $label.Name --repo $fullName --color $label.Color --description $label.Description --force
    if ($LASTEXITCODE -ne 0) { throw "Label setup failed: $($label.Name)" }
}

& $gh api --method PUT "repos/$fullName/actions/permissions/workflow" `
    -f default_workflow_permissions=read `
    -F can_approve_pull_request_reviews=false
if ($LASTEXITCODE -ne 0) { throw 'Default workflow permission setup failed.' }

& $gh api --method PUT "repos/$fullName/vulnerability-alerts"
if ($LASTEXITCODE -ne 0) { throw 'Dependabot alerts setup failed.' }
& $gh api --method PUT "repos/$fullName/automated-security-fixes"
if ($LASTEXITCODE -ne 0) { throw 'Dependabot security updates setup failed.' }

if ($TemplateRepository) {
    & $gh api --method PATCH "repos/$fullName" -F is_template=true
    if ($LASTEXITCODE -ne 0) { throw 'Could not mark the repository as a template.' }
}

$branchProtectionEnabled = $false
if ($Visibility -eq 'public') {
    $protection = [ordered]@{
        required_status_checks = [ordered]@{
            strict = $true
            checks = @([ordered]@{ context = $RequiredCheck; app_id = 15368 })
        }
        enforce_admins = $true
        required_pull_request_reviews = [ordered]@{
            dismiss_stale_reviews = $true
            require_code_owner_reviews = $false
            required_approving_review_count = 0
            require_last_push_approval = $false
        }
        restrictions = $null
        required_linear_history = $true
        allow_force_pushes = $false
        allow_deletions = $false
        required_conversation_resolution = $true
        lock_branch = $false
    }
    ($protection | ConvertTo-Json -Depth 6 -Compress) |
        & $gh api --method PUT "repos/$fullName/branches/main/protection" --input -
    if ($LASTEXITCODE -ne 0) { throw 'Public main branch protection setup failed.' }
    $branchProtectionEnabled = $true
}

Write-Host "PASS: published https://github.com/$fullName"
[pscustomobject]@{
    Repository = $fullName
    Url = "https://github.com/$fullName"
    Visibility = $Visibility
    TemplateRepository = [bool]$TemplateRepository
    BranchProtection = $branchProtectionEnabled
}
