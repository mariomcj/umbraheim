# Gera a build Web (single-thread) em build/web e mede o tamanho do download.
# Requer os export templates 4.7.2 instalados (Editor > Gerenciar Modelos de Exportação).
param([switch]$Debug)
. "$PSScriptRoot\_godot.ps1"

$Out = Join-Path $ProjectRoot "build\web"
New-Item -ItemType Directory -Force $Out | Out-Null
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }

& $Godot --headless --path $ProjectRoot --import | Out-Null
& $Godot --headless --path $ProjectRoot $mode "Web" (Join-Path $Out "index.html")
if ($LASTEXITCODE -ne 0) { Write-Error "Exportação falhou (templates instalados?)"; exit 1 }

Write-Host "`nArquivos da build Web:"
$files = Get-ChildItem $Out -File
$files | Sort-Object Length -Descending | ForEach-Object { "{0,10:N2} MB  {1}" -f ($_.Length / 1MB), $_.Name }
$total = ($files | Measure-Object Length -Sum).Sum
"{0,10:N2} MB  TOTAL (meta da Fase 0: < 30-40 MB até a tela de login)" -f ($total / 1MB)
