# Teste local completo no desktop: servidor headless + N janelas de cliente.
#   .\tools\run_local.ps1               -> servidor + 2 clientes (tela de login)
#   .\tools\run_local.ps1 -Clients 3
#   .\tools\run_local.ps1 -Quick        -> cada cliente entra direto com uma conta e um personagem novos
#   .\tools\run_local.ps1 -Gm           -> servidor aceita comandos de GM
# O banco fica em user://umbraheim.db (pasta de dados da Godot); use -Db ":memory:" para um banco descartável.
param([int]$Clients = 2, [switch]$Quick, [switch]$Gm, [string]$Db = "")
. "$PSScriptRoot\_godot.ps1"

$serverArgs = @("--headless", "--path", "`"$ProjectRoot`"", "--", "--server")
if ($Gm) { $serverArgs += "--allow-gm" }
if ($Db -ne "") { $serverArgs += "--db=$Db" }
Start-Process -FilePath $Godot -ArgumentList $serverArgs
Start-Sleep -Seconds 2
for ($i = 0; $i -lt $Clients; $i++) {
    $x = 40 + ($i * 660)
    $clientArgs = @("--path", "`"$ProjectRoot`"", "--resolution", "640x400", "--position", "$x,80")
    if ($Quick) { $clientArgs += @("--", "--quick-login") }
    Start-Process -FilePath $Godot -ArgumentList $clientArgs
}
Write-Host "Servidor e $Clients cliente(s) iniciados. Feche a janela do servidor para encerrar."
