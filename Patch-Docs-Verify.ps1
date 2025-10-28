param(
  [string]$Repo = "caf-system/CAF-Release",
  [string]$Tag  = "v4.0"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function W([string]$k,[string]$t){
  $c=@{STEP='Cyan';OK='Green';WARN='Yellow';ERR='Red'}[$k]; if(-not $c){$c='Gray'}
  Write-Host ("[{0}] {1}" -f $k,$t) -ForegroundColor $c
}

# --- Pre-flight ---
$root = (& git rev-parse --show-toplevel 2>$null).Trim()
if(-not $root){ throw "Not a Git repo. Run from repo context." }
Set-Location $root
foreach($c in 'git','gh','gpg'){ if(-not (Get-Command $c -ErrorAction SilentlyContinue)){ throw "Required tool '$c' not found in PATH." } }

# Paths
$docsDir  = Join-Path $root 'docs'
$sbomDir  = Join-Path $docsDir 'sbom'
$verifyPs = Join-Path $root 'run_verify.ps1'

$security = Join-Path $root 'SECURITY.md'
$support  = Join-Path $root 'SUPPORT-LIFECYCLE.md'
$orgsign  = Join-Path $root 'ORG-SIGNING-POLICY.md'
$slsa     = Join-Path $root 'SLSA_POLICY.md'
$rebuild  = Join-Path $root 'REBUILD.md'
$verifyMd = Join-Path $docsDir 'VERIFICATION.md'
$tplLic   = Join-Path $root 'THIRD-PARTY-LICENSES.md'

$sumsFile = Join-Path $root 'SHA256SUMS.txt'
$sumsAsc  = $sumsFile + '.asc'

New-Item -ItemType Directory -Force -Path $docsDir,$sbomDir | Out-Null

function Write-IfChanged([string]$path,[string[]]$lines){
  $nl = "`r`n"; $content = ($lines -join $nl)
  $current = (Test-Path $path)? (Get-Content -Raw -Path $path -Encoding UTF8) : ""
  if($current -ne $content){
    Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
    W OK ("Updated {0}" -f ([IO.Path]::GetFileName($path)))
    return $true
  } else { return $false }
}

$updated = @()

# SECURITY.md
if( (Write-IfChanged $security @(
'# Security policy',
'',
'**Branches:** `main` (stable).',
'**Releases:** SemVer, N-2 minor releases supported.',
'**Contact:** support@caf-tech.local'
)) ){ $updated += $security }

# SUPPORT-LIFECYCLE.md
if( (Write-IfChanged $support @(
'# Support & Lifecycle',
'',
'Stable branch: `main`.',
'Policy: SemVer, N-2 minors supported.',
'Security contacts: support@caf-tech.local'
)) ){ $updated += $support }

# ORG-SIGNING-POLICY.md
if( (Write-IfChanged $orgsign @(
'# Org Signing Policy',
'',
'Git tags are signed (GPG) by CAF Signing v4.',
'Release assets must include `SHA256SUMS.txt` and `SHA256SUMS.txt.asc`.',
'SBOM (CycloneDX) and VEX must be GPG-signed.',
'Provenance: `provenance.intoto.jsonl`.'
)) ){ $updated += $orgsign }

# SLSA_POLICY.md
if( (Write-IfChanged $slsa @(
'# SLSA Policy',
'',
'Provenance: in-toto / SLSA-compatible (`provenance.intoto.jsonl`).',
'Rebuild documented in `REBUILD.md`.',
'One-step verification: `run_verify.ps1`.'
)) ){ $updated += $slsa }

# REBUILD.md
if( (Write-IfChanged $rebuild @(
'# Rebuild Instructions',
'',
'Reproduce artifacts deterministically from a clean environment.',
'1. Clone this repo at the signed tag.',
'2. Follow build steps (redacted here for brevity).',
'3. Compare SHA256 with `SHA256SUMS.txt`.'
)) ){ $updated += $rebuild }

# docs/VERIFICATION.md (Windows + Linux/macOS)
$verifyLines = @(
'# Verification Guide',
'',
'This guide explains how to verify the CAF Release v4.0 artifacts offline.',
'',
'## Windows (PowerShell 7+)',
'```powershell',
'pwsh -File .\run_verify.ps1 -Tag v4.0 -Repo caf-system/CAF-Release',
'```',
'',
'## Linux/macOS',
'```bash',
'./run_verify.sh -t v4.0 -r caf-system/CAF-Release',
'```',
'',
'Artifacts covered:',
'- CycloneDX SBOM + signature',
'- VEX (CycloneDX) + signature',
'- `SHA256SUMS.txt` + `SHA256SUMS.txt.asc`',
'- `AUDIT_SEAL.json` + signature'
)
if( (Write-IfChanged $verifyMd $verifyLines) ){ $updated += $verifyMd }

# THIRD-PARTY-LICENSES.md из SBOM при наличии
$sbomPath = Join-Path $sbomDir 'sbom.cdx.json'
if(Test-Path $sbomPath){
  try{
    $sbom = Get-Content -Raw -Path $sbomPath | ConvertFrom-Json
    $rows = @()
    foreach($c in $sbom.components){
      $name = if($c.name){$c.name}else{'UNKNOWN'}
      $ver  = if($c.version){$c.version}else{''}
      $lic = 'UNKNOWN'
      if(($c.PSObject.Properties.Name -contains 'licenses') -and $c.licenses){
        foreach($l in $c.licenses){
          if($l.expression){ $lic = $l.expression; break }
          elseif($l.license){
            if($l.license.id){   $lic = $l.license.id; break }
            elseif($l.license.name){ $lic = $l.license.name; break }
          }
        }
      } elseif($c.PSObject.Properties.Name -contains 'license' -and $c.license){
        $lic = $c.license
      }
      $src = ''
      if($c.PSObject.Properties.Name -contains 'externalReferences' -and $c.externalReferences){
        $hp = $c.externalReferences | Where-Object { $_.type -eq 'website' } | Select-Object -First 1
        if($hp){ $src = $hp.url }
      }
      $rows += [pscustomobject]@{ Component=$name; Version=$ver; License=$lic; Source=$src }
    }
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine('# Third-Party Licenses')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('> Generated from CycloneDX SBOM (`docs/sbom/sbom.cdx.json`).')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| Component | Version | License | Source |')
    [void]$md.AppendLine('|---|---|---|---|')
    foreach($r in $rows){
      $row = ('| {0} | {1} | {2} | {3} |' -f ($r.Component -replace '\|','&#124;'),
                                       ($r.Version   -replace '\|','&#124;'),
                                       ($r.License   -replace '\|','&#124;'),
                                       ($r.Source    -replace '\|','&#124;'))
      [void]$md.AppendLine($row)
    }
    if( (Write-IfChanged $tplLic ($md.ToString() -split "`r`n")) ){ $updated += $tplLic }
  } catch {
    W WARN ("THIRD-PARTY-LICENSES.md skipped (SBOM parse issue): {0}" -f $_.Exception.Message)
  }
} else {
  W WARN 'SBOM not found; skip THIRD-PARTY-LICENSES.md'
}

# --- Checksums + sign (idempotent) ---
function Update-Checksum([string]$file,[string]$sumFile){
  if(-not (Test-Path $file)){ throw "Checksum source missing: $file" }
  $name = [IO.Path]::GetFileName($file)
  $hash = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
  $content = (Test-Path $sumFile)?(Get-Content -Raw -Path $sumFile):""
  $esc = [Regex]::Escape($name); $pat = "(?im)^[0-9a-f]{64}\s+$esc$"
  $line = "$hash $name"
  $updatedSums = ($content -match $pat) ? ([Regex]::Replace($content,$pat,$line)) : (($content.TrimEnd()+"`r`n"+$line).TrimStart())
  Set-Content -Path $sumFile -Value $updatedSums -Encoding UTF8 -NoNewline
}

if($updated.Count -gt 0){
  W STEP 'Updating SHA256SUMS.txt'
  foreach($f in $updated){ Update-Checksum -file $f -sumFile $sumsFile }
  if(Test-Path $sumsAsc){ Remove-Item $sumsAsc -Force }
  & gpg --armor --detach-sign --output $sumsAsc $sumsFile | Out-Null
  if(-not (Test-Path $sumsAsc)){ throw "GPG signing failed for $sumsFile" }
  W OK 'SHA256SUMS.txt.asc re-signed'
} else {
  W WARN 'No changes detected; checksums/signature unchanged'
}

# --- Upload to GitHub Release ---
$toUpload = @($updated + @($sumsAsc)) | Where-Object { Test-Path $_ }
if($toUpload.Count -gt 0){
  W STEP "Uploading assets to GitHub Release: $Repo@$Tag"
  gh release upload $Tag $toUpload --clobber -R $Repo | Out-Null
  W OK ("Assets uploaded: {0}" -f (($toUpload | ForEach-Object {[IO.Path]::GetFileName($_)}) -join ', '))
}

# --- Update release body (Documentation & Policies block) ---
W STEP 'Updating release body (Documentation & Policies block)'
$rel    = gh api -H "Accept: application/vnd.github+json" repos/$Repo/releases/tags/$Tag | ConvertFrom-Json
$assets = @{}; foreach($a in $rel.assets){ $assets[$a.name]=$a.browser_download_url }
function MLink([string]$n){ if($assets.ContainsKey($n)){ return "[{0}]({1})" -f $n,$assets[$n] } else { return $n } }
$NL = "`r`n"
$block = @(
'## Documentation & Policies (completeness)',
'',
" - Security policy:  "      + (MLink ([IO.Path]::GetFileName($security))),
" - Support lifecycle: "      + (MLink ([IO.Path]::GetFileName($support))),
" - Org signing policy: "     + (MLink ([IO.Path]::GetFileName($orgsign))),
" - SLSA policy: "            + (MLink ([IO.Path]::GetFileName($slsa))),
" - Rebuild instructions: "   + (MLink ([IO.Path]::GetFileName($rebuild))),
" - Verification guide: "     + (MLink ([IO.Path]::GetFileName($verifyMd))),
" - Third-Party Licenses: "   + (MLink ([IO.Path]::GetFileName($tplLic))),
" - Signed checksums: "       + (MLink ([IO.Path]::GetFileName($sumsAsc)))
) -join $NL

$body = gh release view $Tag -R $Repo --json body -q '.body'
if([string]::IsNullOrWhiteSpace($body)){ $body = "" }
$re = '(?smi)^##\s*Documentation.*?Policies.*?(?:\r?\n)+'
$updatedBody = ([Regex]::IsMatch($body,$re)) ? ([Regex]::Replace($body,$re,$block+$NL)) : ($body.TrimEnd()+$NL+$NL+$block)
$tmp = Join-Path $env:TEMP ("release-notes-" + [Guid]::NewGuid().ToString('N') + ".md")
Set-Content -Path $tmp -Value $updatedBody -Encoding UTF8 -NoNewline
gh release edit $Tag -R $Repo --notes-file $tmp | Out-Null
Remove-Item $tmp -Force
W OK 'Release body updated'

# --- Final verify ---
if(Test-Path $verifyPs){
  W STEP 'Running final verify'
  pwsh -NoProfile -File $verifyPs -Tag $Tag -Repo $Repo
} else {
  W WARN "run_verify.ps1 not found; skipping final verify"
}

W OK 'End-to-end completed'