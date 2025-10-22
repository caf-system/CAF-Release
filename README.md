# CAF — Compliance Automation Framework (Release v4.0)

Это публичная витрина **институционального пакета** CAF v4.0.

## Артефакты
- ZIP bundle: "artifacts/CAF_DealBundle_4.0.zip"
- Manifest (GPG): "artifacts/DealBundle_Manifest.txt"
- SHA256SUMS (GPG): "artifacts/SHA256SUMS.txt"
- Verifiable materials: **SBOM (SPDX-JSON)** → "docs/sbom/sbom.4.0.spdx.json"
- **SLSA Provenance** → "docs/provenance/provenance.4.0.slsa.json"
- (Опционально) TSA-штампы: в artifacts/*.tsr

### Quick verify
```powershell
Get-FileHash -Algorithm SHA256 .\artifacts/CAF_DealBundle_4.0.zip
# Expected:
0E9FD17D18F1A600ADB0CDD7090543F2BE502AF585ACAB8603415A7D743ED103
```

### Проверка подписи манифеста (GPG)
```powershell
gpg --verify .\artifacts/DealBundle_Manifest.txt.asc .\artifacts/DealBundle_Manifest.txt
```
```powershell
gpg --verify .\artifacts/SHA256SUMS.txt.asc
```

Repo: https://github.com/caf-system/CAF-Release
