# Verification Guide

This guide explains how to verify the CAF Release v4.0 artifacts offline.

## Windows (PowerShell 7+)
```powershell
pwsh -File .\run_verify.ps1 -Tag v4.0 -Repo caf-system/CAF-Release
```

## Linux/macOS
```bash
./run_verify.sh -t v4.0 -r caf-system/CAF-Release
```

Artifacts covered:
- CycloneDX SBOM + signature
- VEX (CycloneDX) + signature
- `SHA256SUMS.txt` + `SHA256SUMS.txt.asc`
- `AUDIT_SEAL.json` + signature