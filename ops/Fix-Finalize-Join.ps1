#requires -Version 7.0
# Fix-Finalize-Join.ps1 — исправляет join "`r`n", проверяет синтаксис и запускает финализацию
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root  = 'C:\cog-ci\CAF-Release'
if (-not (Test-Path -LiteralPath $root)) { throw "Root not found: $root" }
$final = Join-Path $root 'ops\Finalize-CAF-Release.ps1'
if (-not (Test-Path -LiteralPath $final)) { throw "Finalize script not found: $final" }

# Бэкап
$bakDir = Join-Path $root 'ops\bak'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $bakDir -Force | Out-Null
Copy-Item -LiteralPath $final -Destination (Join-Path $bakDir ("Finalize-CAF-Release.ps1.$stamp.bak")) -Force

# Читаем и чиним join-строку: любой вариант внутри скобок меняем на корректную строку с CRLF
$raw   = Get-Content -LiteralPath $final -Raw
$fixed = $raw -replace 'return\s*\(\s*\$lines\s*-join\s*[^)]*\)', 'return ($lines -join "`r`n")'

if ($fixed -eq $raw) {
  Write-Host "[INFO] replacement not applied (already correct?)" -ForegroundColor Yellow
} else {
  Write-Host "[FIX] join() -> CRLF string literal applied" -ForegroundColor Green
}

# Нормализуем CRLF и сохраняем UTF-8 без BOM
$fixed = $fixed -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($final, $fixed, [System.Text.UTF8Encoding]::new($false))

# Быстрая проверка синтаксиса (без исполнения)
try {
  [scriptblock]::Create((Get-Content -LiteralPath $final -Raw)) | Out-Null
  Write-Host "[OK] Syntax check: PASS" -ForegroundColor Green
} catch {
  Write-Host "[FAIL] Syntax error: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

# Откроем файл для взгляда
Start-Process notepad.exe $final

# Запуск финализации (апсерт релиза, страница откроется в браузере)
& (Join-Path $root 'ops\Run-Finalize.ps1') -OpenWeb