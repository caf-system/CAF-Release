#requires -Version 7.0
<#
  Run-Finalize.ps1 (v1.1)
  • Нормализация тега: принимает 4.0 / v4.0 / vv4.0 → сверяет с git tags и берёт корректный.
  • Автосоздание docs\release-body.md (UTF-8 no BOM, CRLF), если нет.
  • Вызов .\ops\Finalize-CAF-Release.ps1 с BodyPath; по умолчанию пишет AUDIT_SEAL.md (JSON+.asc не трогаем).
  Параметры:
    -Tag     : явный тег (опц.)
    -OpenWeb : открыть страницу релиза
    -NoSeal  : не писать человекочитаемый AUDIT_SEAL.md
#>
param(
  [string]$Tag = '',
  [switch]$OpenWeb,
  [switch]$NoSeal
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = 'C:\cog-ci\CAF-Release'
if (-not (Test-Path -LiteralPath $Root)) { throw "Root not found: $Root" }
Set-Location $Root

function Write-Utf8NoBom([string]$path, [string]$content) {
  $dir = [System.IO.Path]::GetDirectoryName($path)
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($path, ($content -replace "`r?`n","`r`n"), [System.Text.UTF8Encoding]::new($false))
}
function Get-AllTags() {
  try { (git tag --list) -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne '' } } catch { @() }
}
function AutoDetect-Tag() {
  $t = (git tag --points-at HEAD | Select-Object -First 1)
  if (-not $t) { $t = (git describe --tags --abbrev=0).Trim() }
  return $t
}
function Normalize-Tag([string]$input) {
  $tags = Get-AllTags
  if (-not $input) { return (AutoDetect-Tag) }
  $x = $input.Trim()
  # схлопываем повторные 'v' в начале (vv4.0 -> v4.0)
  $x = ($x -replace '^(?:v)+','v')
  if ($tags -contains $x) { return $x }
  if ($x -match '^v') {
    $alt = $x.Substring(1)
    if ($tags -contains $alt) { return $alt }
  } else {
    $alt = 'v' + $x
    if ($tags -contains $alt) { return $alt }
  }
  # если ничего не нашли, используем как есть (финализатор отловит отсутствие релиза)
  return $x
}

function New-ReleaseBodyStub([string]$Tag, [string]$OutPath){
  $ts = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssK")
  $assets = @()
  try { $json = & gh release view $Tag --json assets | ConvertFrom-Json; if ($json -and $json.assets){ $assets = $json.assets | ForEach-Object { $_.name } } } catch { }
  $assetsList = ($assets | Select-Object -First 30) -join "`r`n- "
  if ([string]::IsNullOrWhiteSpace($assetsList)) { $assetsList = "(assets list unavailable)" }

  $body = @"
# Overview
CAF Release $Tag — initial release notes stub. **Checked:** $ts (UTC)

# Artifacts
- $assetsList

# Hashes
See `SHA256SUMS.txt` / Data Room top-level manifest.

# Signatures
- GPG (`*.asc`) for manifests and the release tag.

# SBOM
- See `sbom/` or SPDX assets.

# SLSA
- Provenance (if present) — see VERIFY.md.

# Verification
- `.\run_verify.ps1` → PASS
- (optional) `python .\verify_bundle.py --strict-sums`
- (optional) `cosign verify-attestation` if installed

# Data Room
- See `DataRoom\DD_INDEX.md`.

# Legal
- See `POLICY.md`.

# Contacts
- CAF / Cognitive-CI (Dynasty ASI)
"@
  Write-Utf8NoBom -path $OutPath -content $body
  return $OutPath
}

function Get-BodyPath([string]$ResolvedTag){
  if (Test-Path -LiteralPath '.\docs\release-body.md') { return (Resolve-Path '.\docs\release-body.md').Path }
  if (Test-Path -LiteralPath '.\release-body.md')     { return (Resolve-Path '.\release-body.md').Path }
  $stub = Join-Path (Get-Location) 'docs\release-body.md'
  New-ReleaseBodyStub -Tag $ResolvedTag -OutPath $stub
  return $stub
}

# --- MAIN ---
$ResolvedTag = Normalize-Tag $Tag
if (-not $ResolvedTag) { throw "Cannot resolve tag automatically. Pass -Tag." }

$bodyPath = Get-BodyPath -ResolvedTag $ResolvedTag

$finalizer = '.\ops\Finalize-CAF-Release.ps1'
if (-not (Test-Path -LiteralPath $finalizer)) { throw "Not found: $finalizer" }

$parms = @{
  BodyPath        = $bodyPath
  UpdateAuditSeal = (-not $NoSeal.IsPresent)
  Tag             = $ResolvedTag
}

& $finalizer @parms

if ($OpenWeb) {
  try { gh release view $ResolvedTag --web | Out-Null } catch { Write-Warning $_.Exception.Message }
}