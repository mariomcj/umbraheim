# Resolve o executável da Godot (versão console, que mostra o log no terminal).
# Defina a variável de ambiente GODOT_BIN para usar outro caminho.
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ($env:GODOT_BIN) {
    $Godot = $env:GODOT_BIN
} else {
    $Godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
    Write-Error "Godot não encontrada em '$Godot'. Defina `$env:GODOT_BIN com o caminho do executável."
    exit 1
}
