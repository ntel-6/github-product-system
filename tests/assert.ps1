Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "ASSERT FALSE FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "ASSERT EQUAL FAILED: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    if (-not $thrown) { throw "ASSERT THROWS FAILED: $Message" }
}
