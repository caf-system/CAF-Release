param(
  [Parameter(Mandatory=$true)][string]$Repo,   # пример: "caf-system/CAF-Release"
  [Parameter(Mandatory=$true)][string]$Tag,    # пример: "v4.0"
  [string]$VerifyScript = ".\run_verify.ps1"   # опционально; если файла нет — пропустим
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function W([string]$msg,[string]$lvl='INFO'){
  $c = @{ OK='Green'; WARN='Yellow'; ERR='Red'; STEP='Cyan'; INFO='Cyan' }[$lvl]
  if(-not $c){ $c='Cyan' }
  Write-Host ("[{0}] {1}" -f $lvl,$msg) -ForegroundColor $c
}

# 1) Тянем ассеты релиза (чтобы подставить кликабельные ссылки)
W "Fetching release assets" 'STEP'
$rel = gh api -H 'Accept: application/vnd.github+json' "repos/$Repo/releases/tags/$Tag" | ConvertFrom-Json
$assets = @{}
foreach($a in $rel.assets){ $assets[$a.name] = $a.browser_download_url }

function Link([string]$name){
  if($assets.ContainsKey($name)){ return "[$name]($($assets[$name]))" } else { return $name }
}

$NL = [Environment]::NewLine

# 2) Полный body (красивый, с разделами)
$lines = @(
  "## Artifacts",$NL,
  ("- CycloneDX SBOM:      " + (Link "sbom.cdx.json")),
  ("- SBOM signature:      " + (Link "sbom.cdx.json.asc")),
  ("- VEX (CycloneDX):     " + (Link "vex.cdx.json")),
  ("- VEX signature:       " + (Link "vex.cdx.json.asc")),
  ("- SHA256SUMS:          " + (Link "SHA256SUMS.txt")),
  ("- SHA256SUMS signature:" + (Link "SHA256SUMS.txt.asc")),
  ("- AUDIT_SEAL.json:     " + (Link "AUDIT_SEAL.json")),
  ("- AUDIT_SEAL signature:" + (Link "AUDIT_SEAL.json.asc")),
  $NL,
  "## Documentation & Policies",$NL,
  ("- Security policy:     [SECURITY.md](https://github.com/$Repo/blob/$Tag/SECURITY.md)"),
  ("- Support lifecycle:   [SUPPORT-LIFECYCLE.md](https://github.com/$Repo/blob/$Tag/SUPPORT-LIFECYCLE.md)"),
  ("- Org signing policy:  [ORG-SIGNING-POLICY.md](https://github.com/$Repo/blob/$Tag/ORG-SIGNING-POLICY.md)"),
  ("- SLSA policy:         [SLSA_POLICY.md](https://github.com/$Repo/blob/$Tag/SLSA_POLICY.md)"),
  ("- Rebuild instructions:[REBUILD.md](https://github.com/$Repo/blob/$Tag/REBUILD.md)"),
  ("- Verification guide:  [VERIFICATION.md](https://github.com/$Repo/blob/$Tag/VERIFICATION.md)"),
  ("- Third-Party Licenses:[THIRD-PARTY-LICENSES.md](https://github.com/$Repo/blob/$Tag/THIRD-PARTY-LICENSES.md)"),
  $NL,
  "### Quick verification (Windows / PowerShell 7+)",$NL,
  "```powershell",
  "pwsh -NoProfile -File .\run_verify.ps1 -Tag $Tag -Repo $Repo",
  "```"
)

$body = $lines -join $NL

# 3) Надёжная запись через временный файл (ключевой момент: форматируем имя ВНУТРИ скобок)
function Write-ReleaseBody([string]$text){
  $id  = [Guid]::NewGuid().ToString('N')
  $tmp = Join-Path $env:TEMP ("release-body-{0}.md" -f $id)
  Set-Content -Path $tmp -Value $text -Encoding UTF8 -NoNewline
  try {
    $out  = gh release edit $Tag -R $Repo --notes-file $tmp 2>&1
    $code = $LASTEXITCODE
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
  [pscustomobject]@{ ExitCode = $code; Output = ($out -join "`n") }
}

# 4) Сначала пытаемся положить полноценный body, если GitHub ругнётся на 125000 — кладём компактный
W ("Updating release body (full) — length: {0}" -f $body.Length) 'STEP'
$r = Write-ReleaseBody $body
if($r.ExitCode -eq 0){
  W "Release body updated (full)." 'OK'
}
elseif($r.Output -match 'maximum.*is\s*125000' -or $r.Output -match 'Validation Failed'){
  # компактный — только список основных артефактов в одну строку
  $shortNames = @('sbom.cdx.json','vex.cdx.json','SHA256SUMS.txt','AUDIT_SEAL.json') | Where-Object { $assets.ContainsKey($_) }
  $shortLinks = $shortNames | ForEach-Object { Link $_ }
  $compact = "Artifacts: " + ($shortLinks -join ', ')
  $r2 = Write-ReleaseBody $compact
  if($r2.ExitCode -eq 0){
    W "Release body updated (compact fallback)." 'WARN'
  } else {
    W ("GitHub error (compact failed):`n{0}" -f $r2.Output) 'ERR'
    throw "Failed to update release body."
  }
}
else{
  W ("GitHub error (full body):`n{0}" -f $r.Output) 'ERR'
  throw "Failed to update release body."
}

# 5) Локальная финальная проверка (если рядом есть скрипт)
if(Test-Path $VerifyScript){
  W "Running local verify" 'STEP'
  pwsh -NoProfile -File $VerifyScript -Tag $Tag -Repo $Repo
} else {
  W "run_verify.ps1 not found; skipped local verify" 'WARN'
}

W "Done." 'OK'
