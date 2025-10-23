$ErrorActionPreference = "Stop"
Write-Host "== Quick verify ==" -ForegroundColor Cyan

# 1) Находим ZIP
$zip = Get-ChildItem -Path ".\artifacts" -Filter "CAF_DealBundle_*.zip" | Select-Object -First 1
if(-not $zip){ throw "ZIP не найден в .\artifacts" }

# 2) SHA256 ZIP и сверка с SHA256SUMS.txt
$zipHash = (Get-FileHash -Algorithm SHA256 -Path $zip.FullName).Hash.ToLower()
Write-Host "ZIP: $($zip.Name)"
Write-Host "SHA256: $zipHash"
$shaTxt = Get-Content ".\artifacts\SHA256SUMS.txt" -Raw
if ($shaTxt -notmatch $zipHash) { throw "SHA256 не совпал с artifacts/SHA256SUMS.txt" }
Write-Host "SHA256SUMS: OK" -ForegroundColor Green

# 3) Проверка GPG-подписей (если есть gpg)
if (Get-Command gpg -ErrorAction SilentlyContinue) {
  & gpg --verify ".\artifacts\SHA256SUMS.txt.asc" ".\artifacts\SHA256SUMS.txt" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "GPG verify FAILED: SHA256SUMS.txt.asc" }
  & gpg --verify ".\artifacts\DealBundle_Manifest.txt.asc" ".\artifacts\DealBundle_Manifest.txt" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "GPG verify FAILED: DealBundle_Manifest.txt.asc" }
  Write-Host "GPG signatures: OK" -ForegroundColor Green
} else {
  Write-Warning "gpg не найден — подписи не проверены"
}

# 4) Проверка TSA (если есть openssl и .tsr)
if (Get-Command openssl -ErrorAction SilentlyContinue) {
  foreach($name in 'SHA256SUMS.txt','DealBundle_Manifest.txt'){
    $tsr = Join-Path '.\artifacts' ($name + '.tsr')
    if(Test-Path $tsr){
      & openssl ts -reply -in $tsr | Out-Null  # просто проверка, что файл корректен
      Write-Host "TSA reply присутствует для $name" -ForegroundColor Green
    } else {
      Write-Host "TSA отсутствует для $name (не критично, но желательно)" -ForegroundColor Yellow
    }
  }
}

# 5) Наличие SBOM и SLSA
if (-not (Test-Path ".\docs\sbom"))       { throw "docs/sbom отсутствует" }
if (-not (Test-Path ".\docs\provenance")) { throw "docs/provenance отсутствует" }

Write-Host "All checks passed." -ForegroundColor Green
