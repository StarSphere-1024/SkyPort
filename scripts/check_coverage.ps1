# Coverage Check Script for SkyPort (Windows PowerShell)
# Usage: .\scripts\check_coverage.ps1 [-Threshold 70]

param(
    [int]$Threshold = 70
)

$ErrorActionPreference = "Stop"

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path $ScriptPath -Parent
$CoverageFile = Join-Path $ProjectRoot "SkyPort\coverage\lcov.info"

# Check if coverage file exists
if (!(Test-Path $CoverageFile)) {
    Write-Host "❌ Coverage file not found: $CoverageFile" -ForegroundColor Red
    Write-Host "Run 'flutter test --coverage' first" -ForegroundColor Yellow
    exit 1
}

# Parse lcov.info and calculate coverage. Keep this aligned with CI by
# excluding generated localization files.
$TotalLF = 0
$TotalLH = 0
$SkipFile = $false

Get-Content $CoverageFile | ForEach-Object {
    if ($_ -match "^SF:lib[\/\\]l10n[\/\\]app_localizations(_.*)?\.dart$") {
        $SkipFile = $true
    }
    elseif ($_ -match "^SF:") {
        $SkipFile = $false
    }
    elseif (!$SkipFile -and $_ -match "^LF:(\d+)") {
        $TotalLF += [int]$matches[1]
    }
    elseif (!$SkipFile -and $_ -match "^LH:(\d+)") {
        $TotalLH += [int]$matches[1]
    }
}

if ($TotalLF -eq 0) {
    Write-Host "❌ No coverage data found" -ForegroundColor Red
    exit 1
}

$CoveragePct = [math]::Floor(($TotalLH * 100) / $TotalLF)

Write-Host "================================"
Write-Host "   SkyPort Coverage Report"
Write-Host "================================"
Write-Host "Lines Hit:    $TotalLH"
Write-Host "Lines Found:  $TotalLF"
Write-Host "Coverage:     ${CoveragePct}%"
Write-Host "Threshold:    ${Threshold}%"
Write-Host "================================"

if ($CoveragePct -lt $Threshold) {
    Write-Host "❌ FAILED: Coverage ${CoveragePct}% is below threshold ${Threshold}%" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ PASSED: Coverage ${CoveragePct}% meets threshold ${Threshold}%" -ForegroundColor Green
    exit 0
}
