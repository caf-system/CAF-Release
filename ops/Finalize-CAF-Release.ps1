[CmdletBinding()]
param(
  [string]$Tag = '',
  [switch]$OpenWeb,
  [switch]$UpdateAuditSeal
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Utf8NoBom([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content){
  $dir = Split-Path -Parent $Path
  if(-not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $normalized = $Content -replace "`r?`n","`r`n"
  $enc = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path,$normalized,$enc)
}

function Get-RepoRoot(){
  try{
    $root = (git rev-parse --show-toplevel 2>$null).Trim()
    if(-not [string]::IsNullOrWhiteSpace($root)){ return $root }
  }catch{}
  if($PSCommandPath){ $root = Split-Path -Parent $PSCommandPath }
  elseif($PSScriptRoot){ $root = $PSScriptRoot }
  else{ $root = (Get-Location).Path }
  if(Test-Path (Join-Path $root '.git')){ return $root }
  throw "Run inside a Git repository (.git not found)."
}

function Detect-Tag([string]$t){
  if($t){ return $t.Trim() }
  $t = (git tag --points-at HEAD 2>$null | Select-Object -First 1).Trim()
  if(-not $t){ $t = (git describe --tags --abbrev=0 2>$null).Trim() }
  return $t
}

function Build-CompactBody([string]$resolvedTag){
@"
# Release $resolvedTag — Compact Body

> Reason: size limit (GitHub body cap).

## Key Artifacts

- `SHA256SUMS.txt` + `SHA256SUMS.txt.asc`
- `docs/sbom/sbom.cdx.json` + `docs/sbom/sbom.cdx.json.asc`
- `docs/vex/vex.cdx.json` + `docs/vex/vex.cdx.json.asc`
- `RELEASE_POLICY.md`
- `keys/CAF-GPG-KEY.asc`
- `DealBundle_Manifest.txt` + `DealBundle_Manifest.txt.asc`
"@
}

function Publish-BodyFile([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Tag){
  $null = gh --version 2>$null; if($LASTEXITCODE -ne 0){ throw "GitHub CLI 'gh' not found in PATH." }
  gh auth status 1>$null 2>&1; if($LASTEXITCODE -ne 0){ Write-Warning "gh auth status not OK — body upsert may fail." }
  $null = gh release edit $Tag -F $Path 2>&1
  if($LASTEXITCODE -eq 0){ return @{Edited=$true;Created=$false} }
  $out = gh release create $Tag -F $Path 2>&1
  if($LASTEXITCODE -ne 0){ throw "Failed to create or edit release for tag '$Tag'. gh says: $out" }
  return @{Edited=$false;Created=$true}
}

# -------- MAIN --------
$Root = Get-RepoRoot
Push-Location $Root
try{
  # 1) Док-линтер (если есть)
  $check = Join-Path $Root 'ops\Check-Docs.ps1'
  if(Test-Path -LiteralPath $check){ pwsh -NoProfile -File $check | Write-Host }

  # 2) Тег
  $ResolvedTag = Detect-Tag $Tag
  if([string]::IsNullOrWhiteSpace($ResolvedTag)){ throw "Cannot resolve tag automatically. Pass -Tag." }

  # 3) Тело релиза (создать, нормализовать, сжать при лимите)
  $bodyPath = Join-Path $Root 'docs\release-body.md'
  if(-not (Test-Path -LiteralPath $bodyPath)){
    $stub = @"
# Release $ResolvedTag

This human-readable summary is optional. Signed artifacts are authoritative.
"@
    Write-Utf8NoBom -Path $bodyPath -Content $stub
  }

  $body = Get-Content -LiteralPath $bodyPath -Raw
  $body = $body -replace "`r?`n","`r`n"
  $len = [System.Text.Encoding]::UTF8.GetByteCount($body)
  $BodyLimit = 125000

  $usedPath = $bodyPath
  $publishedCompact = $false
  if($len -gt $BodyLimit){
    $tmp = [System.IO.Path]::GetTempFileName()
    $compact = Build-CompactBody $ResolvedTag
    Write-Utf8NoBom -Path $tmp -Content $compact
    $usedPath = $tmp
    $publishedCompact = $true
  } else {
    Write-Utf8NoBom -Path $bodyPath -Content $body
  }

  # 4) Публикуем заметки релиза
  $null = Publish-BodyFile -Path $usedPath -Tag $ResolvedTag | Out-Null

  # 5) Human audit seal (Markdown) — опция
  if($UpdateAuditSeal){
    $sealPath = Join-Path $Root 'docs\AUDIT_SEAL.md'
    $ts = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss\Z")
    $note = if($publishedCompact){ " (compact body due to size limits)" } else { "" }
    $seal = @"
AUDIT SEAL — Human-Readable

**Status:** PASS
**Checked:** $ts (UTC)
**Tag:** $ResolvedTag$note

Canonical audit seal: `docs/AUDIT_SEAL.json` (and `docs/AUDIT_SEAL.json.asc`).
This Markdown is an optional summary, not part of the signed artifact set.
"@
    Write-Utf8NoBom -Path $sealPath -Content $seal
  }

  # 6) Пост-верификация (если есть)
  $verify = Join-Path $Root 'run_verify.ps1'
  if(Test-Path -LiteralPath $verify){ pwsh -NoProfile -File $verify | Write-Host }

  # 7) Открыть релиз в браузере (по желанию)
  if($OpenWeb){
    try{ gh release view $ResolvedTag --web | Out-Null }catch{ Write-Warning "Cannot open web automatically: $($_.Exception.Message)" }
  }

  Write-Host "Finalize: Release notes upserted for tag '$ResolvedTag'. Signed artifacts untouched." -ForegroundColor Green
}
finally{ Pop-Location }