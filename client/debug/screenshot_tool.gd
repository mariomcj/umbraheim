class_name ScreenshotTool
extends Node
## Ferramenta de debug: espera alguns frames, salva a tela em PNG e fecha o jogo.
## Uso: godot -- --screenshot=C:/caminho/shot.png [--screenshot-frames=180]

var output_path: String = "user://screenshot.png"
var _frames_left: int = 180


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-frames="):
			_frames_left = arg.trim_prefix("--screenshot-frames=").to_int()


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left > 0:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(output_path)
	print("[screenshot] %s -> %s | FPS %d" % [error_string(err), ProjectSettings.globalize_path(output_path), Engine.get_frames_per_second()])
	get_tree().quit(0 if err == OK else 1)
