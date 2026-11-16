# Roda os testes automatizados (headless).
. "$PSScriptRoot\_godot.ps1"
& $Godot --headless --path $ProjectRoot --import | Out-Null
& $Godot --headless --path $ProjectRoot -s res://tests/run_tests.gd
exit $LASTEXITCODE
