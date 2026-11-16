extends Node
## Ponto de entrada único. O mesmo projeto vira servidor, cliente ou bot de teste:
##   godot --headless -- --server          servidor dedicado
##   godot -- --url=ws://host:7777         cliente (padrão sem argumentos)
##   godot --headless -- --bot             cliente-robô para testes de rede
##   godot -- --screenshot=user://shot.png captura a tela após alguns frames e sai

const CLIENT_SCENE := "res://client/client_main.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		add_child(GameServer.new())
	elif "--bot" in args:
		add_child(BotClient.new())
	else:
		# tema único da interface (data/config/ui.json -> theme): antes de criar qualquer controle
		UiThemeBuilder.install()
		add_child(load(CLIENT_SCENE).instantiate())
		for arg in args:
			if arg.begins_with("--screenshot="):
				var tool := ScreenshotTool.new()
				tool.output_path = arg.trim_prefix("--screenshot=")
				add_child(tool)
