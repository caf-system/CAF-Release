[CmdletBinding()]
param([string]$Repo="caf-system/CAF-Release",[string]$Tag="v4.0")
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function W($t,$k="STEP"){ $c=@{STEP="Cyan";OK="Green";WARN="Yellow";ERR="Red"}[$k]; Write-Host ("[{0}] {1}" -f $k,$t) -ForegroundColor $c }

# --- Pre-flight ---
$root = (& git rev-parse --show-toplevel 2>$null); if(-not $root){ throw "Run from repo root (use 'root')." }
Set-Location $root
foreach($cmd in "git","gh","gpg"){ if(-not (Get-Command $cmd -ErrorAction SilentlyContinue)){ throw "Required tool '$cmd' not found." } }

$docs    = Join-Path $root "docs"
$sealDir = Join-Path $docs "seal"; New-Item -ItemType Directory -Force -Path $sealDir | Out-Null

$sbom    = Join-Path $docs "sbom\sbom.cdx.json"
$vex     = Join-Path $docs "vex\vex.cdx.json"
$man     = Join-Path $root "DealBundle_Manifest.txt"
$sums    = Join-Path $root "SHA256SUMS.txt"
$sumsAsc = "$sums.asc"
$key     = Join-Path $root "keys\CAF-GPG-KEY.asc"

foreach($f in @($sbom,"$sbom.asc",$vex,"$vex.asc",$man,"$man.asc",$sums,$sumsAsc,$key)){
  if(-not (Test-Path $f)){ throw "Missing file: $f" } else { W "$f found" "OK" }
}

# --- GPG key import (idempotent) ---
& gpg --import $key | Out-Null

# --- Signature check helper ---
function OKSig([string]$asc,[string]$dat){ & gpg --verify $asc $dat 2>$null; return ($LASTEXITCODE -eq 0) }

# --- Local status ---
$ok = @{
  sbom = OKSig "$sbom.asc" $sbom
  vex  = OKSig "$vex.asc"  $vex
  man  = OKSig "$man.asc"  $man
  sums = OKSig $sumsAsc    $sums
}

# --- Release assets map ---
$rel = gh api -H "Accept: application/vnd.github+json" repos/$Repo/releases/tags/$Tag | ConvertFrom-Json
$assets=@{}; foreach($a in $rel.assets){ $assets[$a.name]=$a.browser_download_url }
function L([string]$n){ if($assets.ContainsKey($n)){ return "[${n}](" + $assets[$n] + ")" } else { return $n } }

# --- Build AUDIT_SEAL.json ---
$now = (Get-Date).ToUniversalTime().ToString("o")
$commit = (& git rev-parse --short HEAD).Trim()
$seal = [ordered]@{
  schema  = "https://caf-system.example.org/schemas/audit-seal.v1"
  created = $now
  repo    = $Repo
  tag     = $Tag
  commit  = $commit
  components = @{
    sbom      = @{ ok=$ok.sbom; path="docs/sbom/sbom.cdx.json"; url=($assets["sbom.cdx.json"]) }
    vex       = @{ ok=$ok.vex;  path="docs/vex/vex.cdx.json";   url=($assets["vex.cdx.json"]) }
    manifest  = @{ ok=$ok.man;  path="DealBundle_Manifest.txt"; url=($assets["DealBundle_Manifest.txt"]) }
    checksums = @{ ok=$ok.sums; path="SHA256SUMS.txt";          url=($assets["SHA256SUMS.txt.asc"]) }
  }
  audit_pass = ($ok.sbom -and $ok.vex -and $ok.man -and $ok.sums)
}
$sealPath = Join-Path $sealDir "AUDIT_SEAL.json"
$seal | ConvertTo-Json -Depth 6 | Set-Content -Path $sealPath -Encoding UTF8 -NoNewline
W "AUDIT_SEAL.json written -> $sealPath" "OK"

# --- Sign SEAL ---
$sealAsc = "$sealPath.asc"
if(Test-Path $sealAsc){ Remove-Item $sealAsc -Force }
& gpg --armor --detach-sign --output $sealAsc $sealPath
if(-not (Test-Path $sealAsc)){ throw "GPG signing failed for AUDIT_SEAL.json" }
W "AUDIT_SEAL.json.asc written" "OK"

# --- Update SHA256SUMS (idempotent) + re-sign ---
function Update-Checksum {
  param([string]$file,[string]$sumFile)
  $name=[IO.Path]::GetFileName($file)
  $hash=(Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
  $content=(Test-Path $sumFile)?(Get-Content $sumFile -Raw):""
  $esc=[Regex]::Escape($name); $pat="(?im)^[0-9a-f]{64}\s+$esc$"
  $line="$hash  $name"
  $updated=($content -match $pat)?([Regex]::Replace($content,$pat,$line)):(($content.TrimEnd()+"`r`n"+$line).TrimStart())
  Set-Content -Path $sumFile -Value $updated -NoNewline
}
W "Updating SHA256SUMS.txt"
Update-Checksum -file $sealPath -sumFile $sums
Update-Checksum -file $sealAsc  -sumFile $sums

if(Test-Path $sumsAsc){ Remove-Item $sumsAsc -Force }
& gpg --armor --detach-sign --output $sumsAsc $sums
W "SHA256SUMS.txt.asc re-signed" "OK"

# --- Upload assets to release (clobber) ---
$toUpload = @($sealPath,$sealAsc,$sumsAsc) | Where-Object { Test-Path $_ }
gh release upload $Tag $toUpload --clobber -R $Repo | Out-Null
W ("Assets uploaded: " + (($toUpload | ForEach-Object {[IO.Path]::GetFileName($_)}) -join ', ')) "OK"

# --- Refresh map & update release body (Institutional Seal / Audit Pass) ---
$rel2 = gh api -H "Accept: application/vnd.github+json" repos/$Repo/releases/tags/$Tag | ConvertFrom-Json
$assets=@{}; foreach($a in $rel2.assets){ $assets[$a.name]=$a.browser_download_url }
function L2([string]$n){ if($assets.ContainsKey($n)){ return "[${n}](" + $assets[$n] + ")" } else { return $n } }

$new = @()
$new += "## Institutional Seal / Audit Pass"
$new += ""
$new += "- Audit Seal JSON: "      + (L2 "AUDIT_SEAL.json")
$new += "- Audit Seal Signature: " + (L2 "AUDIT_SEAL.json.asc")
$new += "- Signed checksums: "     + (L2 "SHA256SUMS.txt.asc")
$newText = ($new -join "`r`n")

$body = gh release view $Tag -R $Repo --json body -q ".body"; if([string]::IsNullOrWhiteSpace($body)){ $body="" }
$re = "(?smi)^##\s+Institutional Seal\s*/\s*Audit Pass.*?(?=^\#\#\s|\Z)"
$updated = ([Regex]::IsMatch($body,$re)) ? ([Regex]::Replace($body,$re,$newText)) : ($body.TrimEnd()+"`r`n`r`n"+$newText)
$tmp = Join-Path $env:TEMP ("release-notes-"+[guid]::NewGuid().ToString("N")+".md")
Set-Content -Path $tmp -Value $updated -NoNewline
gh release edit $Tag -R $Repo --notes-file $tmp | Out-Null
Remove-Item $tmp -Force
W "Release body updated with Institutional Seal / Audit Pass" "OK"

# --- Summary ---
Write-Host ""
Write-Host "===== SEAL SUMMARY =====" -ForegroundColor Magenta
Write-Host ("Seal:     {0}" -f $sealPath)
Write-Host ("Seal SIG: {0}" -f $sealAsc)
Write-Host ("SUMS:     {0}" -f $sums)
Write-Host ("SUMS SIG: {0}" -f $sumsAsc)
Write-Host "========================"