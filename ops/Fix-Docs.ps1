#requires -Version 7.0
<#
  Fix-Docs.ps1 — v1.4
  • Правим битые markdown-ссылки в: README.md, VERIFY.md, POLICY.md, RELEASE_POLICY.md, docs\release-body.md
  • Всегда приводим результаты к массиву (@(...)) → .Count/.Length надёжны
  • Ищем цели по имени файла по ВСЕМУ репозиторию; для AUDIT_SEAL.json при -AllowAscFallback ищем *.json.asc по всему дереву и линкуем на него
  • Нормализуем CRLF и UTF-8 no BOM для затронутых (и заодно для нетронутых) MD
  • Подписанные артефакты не трогаем
#>
param(
  [string]$Root = 'C:\cog-ci\CAF-Release',
  [switch]$WhatIf,
  [switch]$AllowAscFallback
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location $Root

$Docs = @('README.md','VERIFY.md','POLICY.md','RELEASE_POLICY.md','docs\release-body.md') |
        Where-Object { Test-Path -LiteralPath $_ }

function Read-Utf8([string]$Path){
  [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))
}
function Write-Utf8NoBom{
  param([Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $crlf = $Content -replace "`r?`n","`r`n"
  [IO.File]::WriteAllText($Path, $crlf, [Text.UTF8Encoding]::new($false))
}
function Strip-Code([string]$Text){
  $t = [regex]::Replace($Text,'```[\s\S]*?```','', 'Singleline')   # block
  $t = [regex]::Replace($t,'`[^`]*`','')                           # inline
  return $t
}
function Get-RelLinks([string]$Text){
  $rx = [regex]'\[[^\]]*\]\(([^)]+)\)'
  $out = [System.Collections.Generic.List[pscustomobject]]::new()
  $clean = Strip-Code $Text
  foreach($m in $rx.Matches($clean)){
    $raw = $m.Groups[1].Value.Trim()
    if ($raw -like 'http*' -or $raw -like 'mailto:*' -or $raw -like '#*') { continue }
    $out.Add([pscustomobject]@{ Raw=$raw })
  }
  return $out
}
function Normalize-Link([string]$u){
  if([string]::IsNullOrWhiteSpace($u)){ return $null }
  $x = $u.Split('#')[0].Trim().Trim('"','''')
  if ($x -match '^\.(/|\\)'){ $x=$x.Substring(2) }
  try { $x=[Uri]::UnescapeDataString($x) } catch { }
  $x = $x -replace '/','\'
  return $x
}
function Find-UniqueByName([string]$fileName){
  $name = [IO.Path]::GetFileName($fileName)
  $all  = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $name })
  if ($all.Length -eq 1) { return $all[0].FullName }
  $pref = @($all | Where-Object { $_.FullName -match '\\docs\\' })
  if ($pref.Length -eq 1) { return $pref[0].FullName }
  return $null
}

$changes = 0
foreach($doc in $Docs){
  $path = (Resolve-Path $doc).Path
  $orig = Read-Utf8 -Path $path
  $text = $orig

  $links = @(Get-RelLinks -Text $text)   # ВСЕГДА массив
  if ($links.Count -eq 0) {
    Write-Utf8NoBom -Path $path -Content $text
    continue
  }

  foreach($ln in $links){
    $norm = Normalize-Link $ln.Raw
    if (-not $norm) { continue }
    $candidate = Join-Path $Root $norm
    if (Test-Path -LiteralPath $candidate) { continue }

    if ($norm -match '(?i)docs\\AUDIT_SEAL\.json$') {
      # Ищем .asc ВЕЗДЕ, берём уникальный
      $ascFound = Find-UniqueByName 'AUDIT_SEAL.json.asc'
      if (-not $ascFound) {
        Write-Warning "Broken link in $doc → $($ln.Raw). Also .asc not found anywhere."
        continue
      }
      if ($AllowAscFallback) {
        $newRel = ([IO.Path]::GetRelativePath($Root, $ascFound)).Replace('\','/')
      } else {
        Write-Warning "AUDIT_SEAL.json missing. Keep canonical link. Use -AllowAscFallback to point to .asc temporarily."
        continue
      }
    } else {
      $found = Find-UniqueByName $norm
      if (-not $found) {
        Write-Warning "Broken link in $doc → $($ln.Raw). No unique match found."
        continue
      }
      $newRel = ([IO.Path]::GetRelativePath($Root, $found)).Replace('\','/')
    }

    $escaped = [regex]::Escape($ln.Raw)
    $text = [regex]::Replace($text, "\($escaped\)", "($newRel)", 1)
    $changes++
    if ($WhatIf) { Write-Host "[PLAN] $doc : $($ln.Raw)  ->  $newRel" -ForegroundColor Cyan }
    else         { Write-Host "[FIX ] $doc : $($ln.Raw)  ->  $newRel" -ForegroundColor Green }
  }

  if (-not $WhatIf -and $text -ne $orig) { Write-Utf8NoBom -Path $path -Content $text }
  else { Write-Utf8NoBom -Path $path -Content $orig }
}

if ($WhatIf) { Write-Host "DONE (WhatIf). Planned changes: $changes" -ForegroundColor Yellow }
else         { Write-Host "DONE. Applied changes: $changes" -ForegroundColor Green }