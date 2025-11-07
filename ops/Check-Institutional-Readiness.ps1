[CmdletBinding()]
param(
    # Корень институционального репозитория
    [string]$RepoRoot = 'C:\cog-ci\CAF-Release-Institutional'
)

# -------------------------------------------------
# Вспомогательное: собираем результаты проверок
# -------------------------------------------------
$results = @()

function Add-CheckResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )
    $results += [pscustomobject]@{
        Check  = $Name
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
        Detail = $Detail
    }
}

Write-Host "[INFO] Checking institutional repo at: $RepoRoot" -ForegroundColor Cyan

# 1. Папка репозитория
$repoExists = Test-Path -LiteralPath $RepoRoot -PathType Container
$detail = if ($repoExists) { $RepoRoot } else { 'Not found' }
Add-CheckResult -Name 'Repo directory exists' -Passed:$repoExists -Detail $detail

if (-not $repoExists) {
    Write-Host "[FAIL] Repo directory not found, further checks skipped." -ForegroundColor Red
    $results | Format-Table -AutoSize
    exit 1
}

# 2. docs/ и ops/
$docsDir = Join-Path $RepoRoot 'docs'
$opsDir  = Join-Path $RepoRoot 'ops'

$docsExists = Test-Path -LiteralPath $docsDir -PathType Container
$detail = if ($docsExists) { $docsDir } else { 'Not found' }
Add-CheckResult -Name 'docs directory exists' -Passed:$docsExists -Detail $detail

$opsExists  = Test-Path -LiteralPath $opsDir -PathType Container
$detail = if ($opsExists) { $opsDir } else { 'Not found' }
Add-CheckResult -Name 'ops directory exists' -Passed:$opsExists -Detail $detail

# 3. Обязательные файлы
$requiredFiles = @(
    'docs\INSTITUTIONAL_OVERVIEW.md',
    'docs\DD_ACCESS_AND_USAGE.md',
    'docs\OPS_GUIDE.md',
    'docs\VERIFY_INSTITUTIONAL_PACKAGE.md',
    'ops\Verify-Institutional-Package.ps1',
    'ops\Upload-Institutional-Assets.ps1',
    'README.md'
)

foreach ($relPath in $requiredFiles) {
    $fullPath = Join-Path $RepoRoot $relPath
    $exists   = Test-Path -LiteralPath $fullPath -PathType Leaf
    $detail   = if ($exists) { $fullPath } else { 'Not found' }
    Add-CheckResult -Name "File exists: $relPath" -Passed:$exists -Detail $detail
}

# 4. Git-репозиторий
$gitDir  = Join-Path $RepoRoot '.git'
$gitRepo = Test-Path -LiteralPath $gitDir -PathType Container
$detail  = if ($gitRepo) { $gitDir } else { 'No .git directory' }
Add-CheckResult -Name 'Git repository present' -Passed:$gitRepo -Detail $detail

if ($gitRepo) {
    # 5. Чистота рабочего дерева
    $gitStatusOutput = & git -C $RepoRoot status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) {
        Add-CheckResult -Name 'Git status check' -Passed:$false -Detail 'git status failed'
    } else {
        $joined  = $gitStatusOutput -join "`n"
        $isClean = [string]::IsNullOrWhiteSpace($joined)
        $detail  = if ($isClean) { 'No local changes' } else { 'Uncommitted changes present' }
        Add-CheckResult -Name 'Working tree clean' -Passed:$isClean -Detail $detail
    }

    # 6. Текущая ветка
    $branchName = & git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $branchName) {
        $branchName = $branchName.Trim()
        $isMain     = $branchName -eq 'main'
        Add-CheckResult -Name 'Current branch is main' -Passed:$isMain -Detail $branchName
    } else {
        Add-CheckResult -Name 'Current branch detection' -Passed:$false -Detail 'Failed to detect branch'
    }

    # 7. Синхронизация с origin/main
    $shortStatus = & git -C $RepoRoot status -sb 2>$null
    if ($LASTEXITCODE -eq 0 -and $shortStatus) {
        # shortStatus может быть строкой или массивом строк — нормализуем
        if ($shortStatus -is [string]) {
            $firstLine = ($shortStatus -split "`n")[0]
        } else {
            $firstLine = $shortStatus[0]
        }
        $firstLine   = [string]$firstLine
        $hasDiverged = $firstLine -match '\[ahead|\[behind'
        $detail      = $firstLine.Trim()
        Add-CheckResult -Name 'Branch in sync with origin' -Passed:(!$hasDiverged) -Detail $detail
    } else {
        Add-CheckResult -Name 'Branch/origin sync check' -Passed:$false -Detail 'git status -sb failed'
    }
}

# -------------------------------------------------
# Вывод результата
# -------------------------------------------------
Write-Host ""
Write-Host "Institutional readiness summary:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$hasFail = $results.Status -contains 'FAIL'

Write-Host ""
if ($hasFail) {
    Write-Host "[RESULT] Some checks FAILED – see table above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "[RESULT] All institutional checks PASSED." -ForegroundColor Green
    exit 0
}
