# Add-CycloneDX-And-RefreshRelease.ps1 (v1.1)
[CmdletBinding()]
param([string]$Repo="caf-system/CAF-Release",[string]$Tag="v4.0")
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function W([string]$t,[string]$k="STEP"){ $c=@{STEP="Cyan";OK="Green";WARN="Yellow";ERR="Red"}[$k]; Write-Host ("[{0}] {1}" -f $k,$t) -ForegroundColor $c }
W "Pre-flight checks"
$repoRoot = (& git rev-parse --show-toplevel 2>$null); if(-not $repoRoot){ throw "Not a git repository. Open the CAF-Release repo root first." }; $repoRoot=$repoRoot.Trim()
if(-not (Test-Path (Join-Path $repoRoot '.git'))){ throw "No .git at $repoRoot" }; Set-Location $repoRoot
$originUrl = (& git config --get remote.origin.url 2>$null); if($originUrl -and ($originUrl -notmatch 'caf-system/CAF-Release')){ throw "Wrong repo: $originUrl" }
foreach($cmd in "git","gh","gpg","openssl"){ if(-not (Get-Command $cmd -ErrorAction SilentlyContinue)){ throw "Required tool '$cmd' not found in PATH." } }
$binDir = Join-Path $env:LOCALAPPDATA "caf\bin"; New-Item -ItemType Directory -Force -Path $binDir | Out-Null; $env:PATH="$binDir;$env:PATH"
$sbomDir = Join-Path $repoRoot "docs\sbom"; New-Item -ItemType Directory -Force -Path $sbomDir | Out-Null
$spdxPath = Join-Path $sbomDir "sbom.spdx.json"; $cdxPath = Join-Path $sbomDir "sbom.cdx.json"; $cdxAsc="$cdxPath.asc"
$sumsFile = Join-Path $repoRoot "SHA256SUMS.txt"; $sumsAsc="$sumsFile.asc"

function Get-CycloneDX {
  $candidate = Join-Path $binDir "cyclonedx.exe"; if(Test-Path $candidate){ return $candidate }
  W "Locating cyclonedx-cli via GitHub Releases"
  try{
    $rel = gh api -H "Accept: application/vnd.github+json" repos/CycloneDX/cyclonedx-cli/releases/latest | ConvertFrom-Json
    $asset = $rel.assets | Where-Object { $_.name -match 'cyclonedx.*win.*x64.*\.(exe|zip)$' } | Select-Object -First 1
    if($asset){
      $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("cdx-"+[guid]::NewGuid().ToString("N"))); $dest=Join-Path $tmp $asset.name
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest
      if($asset.name -match '\.exe$'){ Copy-Item $dest $candidate -Force; return $candidate }
      Expand-Archive -Path $dest -DestinationPath $tmp -Force
      $exe = Get-ChildItem -Path $tmp -Recurse -Filter "cyclonedx*.exe" | Select-Object -First 1
      if($exe){ Copy-Item $exe.FullName $candidate -Force; return $candidate }
    }
  } catch { W "GitHub API lookup failed: $($_.Exception.Message)" "WARN" }
  W "Fallback: winget (user scope)"; try{ winget install --id CycloneDX.CycloneDX --source winget --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null; $cmd=Get-Command cyclonedx -ErrorAction SilentlyContinue; if($cmd){ Copy-Item $cmd.Source $candidate -Force; return $candidate } } catch { W "winget fallback failed: $($_.Exception.Message)" "WARN" }
  W "Final fallback: direct download"; $direct="https://github.com/CycloneDX/cyclonedx-cli/releases/latest/download/cyclonedx-win-x64.exe"
  try{ Invoke-WebRequest -Uri $direct -OutFile $candidate; if(Test-Path $candidate){ return $candidate } } catch {}
  throw "Unable to obtain cyclonedx-cli for Windows x64."
}
$cyclonedx = Get-CycloneDX; W "cyclonedx path: $cyclonedx" "OK"

function New-CycloneDX {
  param([string]$cdxExe,[string]$spdx,[string]$out,[string]$root)
  if(Test-Path $spdx){
    W "Converting SPDX → CycloneDX (JSON, v1.6)"; & $cdxExe convert --input-file $spdx --input-format spdxjson --output-file $out --output-format json --output-version v1_6
  } else {
    W "SPDX not found — generating SBOM from tracked files only (git ls-files)" "WARN"
    $tmpSrc = Join-Path $env:TEMP ("cdx-src-"+[guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Force -Path $tmpSrc | Out-Null
    $tracked = (& git ls-files); if(-not $tracked){ throw "git ls-files returned nothing. Is this repo empty?" }
    foreach($rel in $tracked){ if([string]::IsNullOrWhiteSpace($rel)){ continue }; $src=Join-Path $root $rel; $dst=Join-Path $tmpSrc $rel; New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null; Copy-Item -LiteralPath $src -Destination $dst -Force }
    & $cdxExe add files --no-input --output-file $out --output-format json --base-path $tmpSrc
    Remove-Item -LiteralPath $tmpSrc -Recurse -Force -ErrorAction SilentlyContinue
  }
  if(-not (Test-Path $out)){ throw "SBOM generation failed: $out not created." }
  W "SBOM ready: $out" "OK"
}
New-CycloneDX -cdxExe $cyclonedx -spdx $spdxPath -out $cdxPath -root $repoRoot

function Sign-Ascii([string]$file,[string]$asc){
  if(-not (Test-Path $file)){ throw "Cannot sign: file not found ($file)" }
  W "Signing (ASCII-armored) $([IO.Path]::GetFileName($file))"
  if(Test-Path $asc){ Remove-Item $asc -Force }
  & gpg --armor --detach-sign --output $asc $file
  if(-not (Test-Path $asc)){ throw "GPG signing failed for $file" }
  W "Signature: $asc" "OK"
}
Sign-Ascii -file $cdxPath -asc $cdxAsc

function Update-Checksum{ param([string]$file,[string]$sumFile)
  if(-not (Test-Path $file)){ throw "Checksum source missing: $file" }
  $name=[IO.Path]::GetFileName($file); $hash=(Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
  $lines=(Test-Path $sumFile)?(Get-Content $sumFile -Raw):""; $pattern="(?im)^[0-9a-f]{64}\s+\Q$name\E$"; $newLine="$hash  $name"
  $updated=($lines -match $pattern)?([Regex]::Replace($lines,$pattern,$newLine)):(($lines.TrimEnd()+"`r`n"+$newLine).TrimStart())
  Set-Content -Path $sumFile -Value $updated -NoNewline; W "Checksums updated for $name" "OK"
}
W "Updating SHA256SUMS.txt"; Update-Checksum -file $cdxPath -sumFile $sumsFile; Update-Checksum -file $cdxAsc -sumFile $sumsFile
W "Signing SHA256SUMS.txt"; if(Test-Path $sumsAsc){ Remove-Item $sumsAsc -Force }; & gpg --armor --detach-sign --output $sumsAsc $sumsFile; if(-not (Test-Path $sumsAsc)){ throw "GPG signing failed for $sumsFile" }; W "Signature: $sumsAsc" "OK"

W "Uploading assets to GitHub Release: $Repo@$Tag"
$toUpload=@($cdxPath,$cdxAsc,$sumsAsc)|Where-Object{Test-Path $_}; if($toUpload.Count -eq 0){ throw "Nothing to upload" }
& gh release upload $Tag $toUpload --clobber -R $Repo | Out-Null
$uploadedNames = $toUpload | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object -Unique
W ("Assets uploaded (clobber on): " + ($uploadedNames -join ', ')) "OK"

W "Refreshing release notes with Institutional additions"
$releaseJson = gh api -H "Accept: application/vnd.github+json" repos/$Repo/releases/tags/$Tag | ConvertFrom-Json
$assetsMap=@{}; foreach($a in $releaseJson.assets){ $assetsMap[$a.name]=$a.browser_download_url }
function MkLink([string]$name){ if($assetsMap.ContainsKey($name)){ return "[${name}](" + $assetsMap[$name] + ")" } else { return $name } }
$newBlock=@(); $newBlock+="## Institutional additions"; $newBlock+=""; $newBlock+="- CycloneDX SBOM (JSON): "+(MkLink "sbom.cdx.json"); $newBlock+="- Signature (ASCII-armored): "+(MkLink "sbom.cdx.json.asc"); $newBlock+="- Signed checksums: "+(MkLink "SHA256SUMS.txt.asc")
$newBlockText=($newBlock -join "`r`n")
$currentBody = gh release view $Tag -R $Repo --json body -q ".body"; if([string]::IsNullOrWhiteSpace($currentBody)){ $currentBody="" }
$regex="(?smi)^##\s+Institutional additions.*?(?=^\#\#\s|\Z)"
$updatedBody=([Regex]::IsMatch($currentBody,$regex))?([Regex]::Replace($currentBody,$regex,$newBlockText)):($currentBody.TrimEnd()+"`r`n`r`n"+$newBlockText)
$tmpNotes = Join-Path $env:TEMP ("release-notes-"+[guid]::NewGuid().ToString("N")+".md"); Set-Content -Path $tmpNotes -Value $updatedBody -NoNewline; & gh release edit $Tag -R $Repo --notes-file $tmpNotes | Out-Null; Remove-Item $tmpNotes -Force
W "Release body updated." "OK"

$commit = (& git rev-parse --short HEAD 2>$null); $commit = ([string]::IsNullOrWhiteSpace($commit))? "n/a" : $commit.Trim()
Write-Host "`n===== SUMMARY =====" -ForegroundColor Magenta
Write-Host ("Repo: {0}" -f $Repo); Write-Host ("Tag:  {0}" -f $Tag); Write-Host ("Commit: {0}" -f $commit)
Write-Host ("SBOM: {0}" -f $cdxPath); Write-Host ("SIG:  {0}" -f $cdxAsc); Write-Host ("SUMS: {0}" -f $sumsFile); Write-Host ("SUMS SIG: {0}" -f $sumsAsc)
Write-Host "Links:"; Write-Host ("  sbom.cdx.json       → {0}" -f ($assetsMap["sbom.cdx.json"]      | ForEach-Object { $_ }))
Write-Host ("  sbom.cdx.json.asc   → {0}" -f ($assetsMap["sbom.cdx.json.asc"]  | ForEach-Object { $_ }))
Write-Host ("  SHA256SUMS.txt.asc  → {0}" -f ($assetsMap["SHA256SUMS.txt.asc"] | ForEach-Object { $_ }))
Write-Host "===================="
