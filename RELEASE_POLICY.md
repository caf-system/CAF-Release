# Release Policy

**Versioning:** Semantic Versioning (SemVer).
- **MAJOR**: backward-incompatible changes
- **MINOR**: backward-compatible features
- **PATCH**: backward-compatible bug fixes

**Acceptance gates (must pass before public release):**
1. Artifact set complete: Deal bundle, manifest, signed checksums (SHA256SUMS.txt.asc), public key, SBOM (CycloneDX) + signature, VEX + signature, provenance (SLSA/in-toto).
2. Reproducibility: REBUILD.md ensures deterministic rebuild; one-step verification (un_verify.ps1).
3. Supply-chain transparency: signed git tag, assets match checksums, core policies present (SECURITY.md, SLSA_POLICY.md, ORG-SIGNING-POLICY.md, SUPPORT-LIFECYCLE.md).
4. Security: vulnerabilities disclosed via VEX; security contacts in SECURITY.md.
5. Documentation: docs/VERIFICATION.md, RELEASE_POLICY.md, ATTRIBUTION/THIRD-PARTY-LICENSES.md kept current.

**Provenance & Traceability:**
- SLSA provenance: provenance.intoto.jsonl
- Signed git tag: v4.0