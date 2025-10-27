#requires -Version 7.0
<#
  Check-Docs.ps1 — v3.2
  • В сообщениях FAIL печатается документ-источник (имя файла)
  • Остальное: как v3.1 — игнор code-fences, нормализация ссылок, POLICY.md ИЛИ RELEASE_POLICY.md
#>
param([string]$Root='C:\cog-ci\CAF-Release')

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Set-Location $Root

function Test-Utf8NoBomEol([string]$path){
  $bytes=[IO.File]::ReadAllBytes($path)
  $bom=($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF)
  $text=[Text.Encoding]::UTF8.GetString($bytes)
  $hasCRLF=($text -match "`r`n"); $hasLFOnly=($text -match "(?<!`r)`n")
  $eol= if($hasCRLF -and -not $hasLFOnly){'CRLF'} elseif($hasCRLF -and $hasLFOnly){'Mixed'} else{'LF'}
  [pscustomobject]@{Bom=$bom;Eol=$eol;Text=$text}
}
function Strip-Code([string]$text){
  $t=[regex]::Replace($text,'```[\s\S]*?```','', 'Singleline')
  $t=[regex]::Replace($t,'`[^`]*`','')
  return $t
}
function Get-RelativeLinks([string]$text){
  $list=[System.Collections.Generic.List[string]]::new()
  $clean=Strip-Code $text
  $rx=[regex]'\[[^\]]*\]\(([^)]+)\)'
  foreach($m in $rx.Matches($clean)){
    $u=$m.Groups[1].Value.Trim()
    if ($u -like 'http*' -or $u -like 'mailto:*' -or $u -like '#*'){ continue }
    $list.Add($u)
  }
  return $list
}
function Normalize-Link([string]$u){
  if([string]::IsNullOrWhiteSpace($u)){ return $null }
  $u=$u.Split('#')[0].Trim().Trim('"','''')
  if ($u -match '^\.(/|\\)'){ $u=$u.Substring(2) }
  try { $u=[Uri]::UnescapeDataString($u) } catch { }
  $u=$u -replace '/','\'
  return $u
}

$errors=0; $warnings=0
function Check-One{ param([string]$doc)
  if(-not (Test-Path -LiteralPath $doc)){ Write-Host "[FAIL] $doc not found" -ForegroundColor Red; $script:errors++; return }
  Write-Host "[OK]   $doc found" -ForegroundColor Green
  $abs=(Resolve-Path $doc).Path
  $meta=Test-Utf8NoBomEol $abs
  if($meta.Bom){ Write-Host "  [WARN] BOM present → should be UTF-8 without BOM" -ForegroundColor Yellow; $script:warnings++ }
  if($meta.Eol -ne 'CRLF'){ Write-Host "  [WARN] EOL=$($meta.Eol) → should be CRLF" -ForegroundColor Yellow; $script:warnings++ }
  $links=Get-RelativeLinks $meta.Text
  foreach($rel in $links){
    $n=Normalize-Link $rel; if(-not $n){ continue }
    $candidate=Join-Path $Root $n
    if(-not (Test-Path -LiteralPath $candidate)){
      Write-Host "  [FAIL] $doc → broken link: $rel" -ForegroundColor Red
      Write-Host "        Tried: $candidate" -ForegroundColor DarkGray
      $script:errors++
    }
  }
}

$must=@('README.md','VERIFY.md','docs\release-body.md')
foreach($m in $must){ Check-One $m }

$policy=@('POLICY.md','RELEASE_POLICY.md') | Where-Object { Test-Path -LiteralPath $_ }
if($policy.Count -gt 0){ foreach($p in $policy){ Check-One $p } }
else { Write-Host "[FAIL] POLICY.md or RELEASE_POLICY.md not found" -ForegroundColor Red; $errors++ }

if(Test-Path -LiteralPath 'VERIFY.md'){
  $t=(Get-Content -LiteralPath 'VERIFY.md' -Raw)
  if($t -notmatch 'run_verify\.ps1'){
    Write-Host "  [WARN] VERIFY.md: add explicit step with .\run_verify.ps1" -ForegroundColor Yellow
    $warnings++
  }
}

Write-Host "`n===== DOCS CHECK SUMMARY ====="
Write-Host ("Errors:   {0}" -f $errors)
Write-Host ("Warnings: {0}" -f $warnings)
if($errors -gt 0){ exit 1 } else { exit 0 }