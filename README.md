# CAF — Compliance Automation Framework (Release v4.0)



## Quick verify (локально)

**1) Проверка SHA256 ZIP:**

```powershell
Get-FileHash -Algorithm SHA256 "artifacts/CAF_DealBundle_4.0.zip"
```

**Ожидаемая сумма:**

```text
0e9fd17d18f1a600adb0cdd7090543f2be502af585acab8603415a7d743ed103
```

**2) Проверка подписи манифеста (GPG):**

```powershell
gpg --verify "artifacts/DealBundle_Manifest.txt.asc" "artifacts/DealBundle_Manifest.txt"
```

**3) Проверка подписи SHA256SUMS (GPG):**

```powershell
gpg --verify "artifacts/SHA256SUMS.txt.asc" "artifacts/SHA256SUMS.txt"
```

