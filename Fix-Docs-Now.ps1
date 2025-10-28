[CmdletBinding()]
param([string]$Repo="caf-system/CAF-Release",[string]$Tag="v4.0")
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function W($t,$k="STEP"){ $c=@{STEP="Cyan";OK="Green";WARN="Yellow";ERR="Red"}[$k]; Write-Host ("[{0}] {1}" -f $k,$t) -ForegroundColor $c }
$NL = [Environment]::NewLine

# --- Pre-flight ---
$root = (& git rev-parse --show-toplevel 2>$null); if(-not $root){ throw "Run from repo root (use 'root')." }
Set-Location $root
foreach($c in "git","gh","gpg"){ if(-not (Get-Command $c -ErrorAction SilentlyContinue)){ throw "Required tool '$c' not found." } }

$docs = Join-Path $root "docs"; New-Item -ItemType Directory -Force -Path $docs | Out-Null
$verif = Join-Path $docs "VERIFICATION.md"
$codeowners = Join-Path $root "CODEOWNERS"
$gattr = Join-Path $root ".gitattributes"
$sums  = Join-Path $root "SHA256SUMS.txt"
$sumsAsc = "$sums.asc"

# --- VERIFICATION.md (Win + Linux/macOS, конкретные команды) ---
$verifMd = @(
"# Verification Guide",
"",
"## Windows (PowerShell 7+)",
"```powershell",
"pwsh -File .\run_verify.ps1 -Tag v4.0 -Repo caf-system/CAF-Release",
"```",
"",
"## Linux/macOS (GPG + sha256sum)",
"```bash",
"# 1) Import key",
"gpg --import keys/CAF-GPG-KEY.asc",
"",
"# 2) Verify checksums signature and sums",
"gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt",
"sha256sum -c SHA256SUMS.txt | grep -E 'OK$'",
"",
"# 3) Verify artifact signatures",
"gpg --verify docs/sbom/sbom.cdx.json.asc docs/sbom/sbom.cdx.json",
"gpg --verify docs/vex/vex.cdx.json.asc  docs/vex/vex.cdx.json",
"gpg --verify DealBundle_Manifest.txt.asc DealBundle_Manifest.txt",
"```",
"",
"Artifacts covered:",
"- CycloneDX SBOM + signature",
"- VEX (CycloneDX) + signature",
"- SHA256SUMS.txt + SHA256SUMS.txt.asc",
"- AUDIT_SEAL.json + signature"
) -join $NL
Set-Content -Path $verif -Value $verifMd -Encoding UTF8 -NoNewline
W "VERIFICATION.md written" "OK"

# --- CODEOWNERS ---
if(-not (Test-Path $codeowners)){
  $co = @(
    "# Default code owners (adjust to your org)",
    "*       @caf-system/core",
    "docs/*  @caf-system/docs"
  ) -join $NL
  Set-Content -Path $codeowners -Value $co -Encoding UTF8 -NoNewline
  W "CODEOWNERS created" "OK"
} else { W "CODEOWNERS exists" "OK" }

# --- .gitattributes ---
if(-not (Test-Path $gattr)){
  $ga = @(
    "* text=auto",
    "*.ps1 eol=crlf",
    "*.sh  eol=lf"
  ) -join $NL
  Set-Content -Path $gattr -Value $ga -Encoding UTF8 -NoNewline
  W ".gitattributes created" "OK"
} else { W ".gitattributes exists" "OK" }

# --- Update SHA256SUMS + re-sign (идемпотентно) ---
function Update-Checksum{
  param([string]$file,[string]$sumFile)
  $name = [IO.Path]::GetFileName($file)
  $hash = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
  $content = (Test-Path $sumFile) ? (Get-Content $sumFile -Raw) : ""
  $pat = "(?im)^[0-9a-f]{64}\s+$([Regex]::Escape($name))$"
  $line = "$hash  $name"
  $updated = ($content -match $pat) ? ([Regex]::Replace($content,$pat,$line)) : (($content.TrimEnd()+$NL+$line).TrimStart())
  Set-Content -Path $sumFile -Value $updated -NoNewline
}

$changed=@()
foreach($f in @($verif,$codeowners,$gattr)){
  if(Test-Path $f){ Update-Checksum -file $f -sumFile $sums; $changed += [IO.Path]::GetFileName($f) }
}
if($changed.Count -gt 0){
  if(Test-Path $sumsAsc){ Remove-Item $sumsAsc -Force }
  & gpg --armor --detach-sign --output $sumsAsc $sums
  if(-not (Test-Path $sumsAsc)){ throw "GPG signing failed for $sums" }
  W ("SHA256SUMS updated for: " + ($changed -join ', ')) "OK"
  W "SHA256SUMS.txt.asc re-signed" "OK"
} else { W "No checksum updates were needed" "WARN" }

# --- Upload assets & update release body ---
$toUpload = @($verif,$codeowners,$gattr,$sumsAsc) | Where-Object { Test-Path $_ }
gh release upload $Tag $toUpload --clobber -R $Repo | Out-Null
W ("Assets uploaded: " + (($toUpload | ForEach-Object {[IO.Path]::GetFileName($_)}) -join ', ')) "OK"

$rel = gh api -H "Accept: application/vnd.github+json" repos/$Repo/releases/tags/$Tag | ConvertFrom-Json
$assets=@{}; foreach($a in $rel.assets){ $assets[$a.name]=$a.browser_download_url }
function L([string]$n){ if($assets.ContainsKey($n)){ return "[${n}](" + $assets[$n] + ")" } else { return $n } }

$new = @(
  "## Documentation & Policies (completeness)",
  "",
  "- Security policy:           " + (L "SECURITY.md"),
  "- Support lifecycle:         " + (L "SUPPORT-LIFECYCLE.md"),
  "- Org signing policy:        " + (L "ORG-SIGNING-POLICY.md"),
  "- SLSA policy:               " + (L "SLSA_POLICY.md"),
  "- Rebuild instructions:      " + (L "REBUILD.md"),
  "- Verification guide:        " + (L "VERIFICATION.md"),
  "- Third-Party Licenses:      " + (L "THIRD-PARTY-LICENSES.md"),
  "- Signed checksums:          " + (L "SHA256SUMS.txt.asc")
) -join $NL

$body = gh release view $Tag -R $Repo --json body -q ".body"; if([string]::IsNullOrWhiteSpace($body)){ $body="" }
$re = "(?smi)^##\s+Documentation\s*&\s*Policies.*?(?=^\#\#\s|\Z)"
$updated = ([Regex]::IsMatch($body,$re)) ? ([Regex]::Replace($body,$re,$new)) : ($body.TrimEnd()+$NL+$NL+$new)
$tmp = Join-Path $env:TEMP ("release-notes-"+[guid]::NewGuid().ToString("N")+".md")
Set-Content -Path $tmp -Value $updated -NoNewline
gh release edit $Tag -R $Repo --notes-file $tmp | Out-Null
Remove-Item $tmp -Force
W "Release body updated (Documentation & Policies)" "OK"

# --- Final verify ---
W "Running final verify"
pwsh -File .\run_verify.ps1 -Tag $Tag -Repo $Repo