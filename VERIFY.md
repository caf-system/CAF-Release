<!-- AUDIT-SEAL:v4.0:653f4f6dd21ba28ad12567f778b4607dc91a920d:2D13A5F63EDE2DB61646141FA922472D00E94B95 -->
# VERIFY — CAF Release

Этот файл описывает **минимально достаточные** шаги для локальной проверки релиза.
Кодировка: UTF-8 без BOM. Окончания строк: CRLF.

## Быстрая проверка (≈ 60 секунд)

```powershell
pwsh -NoProfile -File .\run_verify.ps1
```

## Полная проверка
1) Предусловия
```powershell
gh auth status
gpg --version
pwsh -v
```
2) Проверка манифестов и тега
```powershell
pwsh -NoProfile -File .\run_verify.ps1
$tag = (git tag --points-at HEAD | Select-Object -First 1); if (-not $tag) { $tag = (git describe --tags --abbrev=0).Trim() }
git tag -v $tag
```
3) Основные артефакты
- [`SHA256SUMS.txt`](./SHA256SUMS.txt) + [`SHA256SUMS.txt.asc`](./SHA256SUMS.txt.asc)
- [`docs/sbom/sbom.cdx.json`](./docs/sbom/sbom.cdx.json)
- [`docs/sbom/vex.cdx.json`](docs/vex/vex.cdx.json)
- [`DealBundle_Manifest.txt`](./DealBundle_Manifest.txt) + [`DealBundle_Manifest.txt.asc`](./DealBundle_Manifest.txt.asc)
- Audit seal: [`docs/AUDIT_SEAL.json`](docs/seal/AUDIT_SEAL.json.asc) + [`docs/AUDIT_SEAL.json.asc`](docs/seal/AUDIT_SEAL.json.asc)
- GPG key: [`keys/CAF-GPG-KEY.asc`](./keys/CAF-GPG-KEY.asc)

4) Опционально
```powershell
# если есть verify_bundle.py
python .\verify_bundle.py --strict-sums
# если есть cosign
# cosign verify-attestation --type spdx <subject>
# cosign verify-attestation --type slsaprovenance <subject>
```

> Подписанные артефакты и тег **не изменяются**; release-notes правятся только через temp-файл и `gh release edit`.
