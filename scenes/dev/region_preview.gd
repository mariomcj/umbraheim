extends Node
## Prévia de uma região com o clima aplicado (AmbienceDirector), sem servidor: para conferir luz,
## névoa, partículas e materiais das regiões de evento, que o "goto" não abre.
## Rodar: godot --path . res://scenes/dev/region_preview.tscn -- --region=castelo [--at=0,-12] [--dist=14]
##        [--shot=C:/caminho/saida.png] [--frames=240] [--profile=baixo|medio|alto]
## A cena vem de data/regions/<região>.json -> "scene".

var _frames := 0
var _max_frames := 240
var _shot := ""


func _ready() -> void:
	var region_id := "ruinas"
	var at := Vector2.ZERO
	var dist := 18.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--region="):
			region_id = arg.trim_prefix("--region=")
		elif arg.begins_with("--at="):
			var p := arg.trim_prefix("--at=").split(",")
			at = Vector2(p[0].to_float(), p[1].to_float())
		elif arg.begins_with("--dist="):
			dist = arg.trim_prefix("--dist=").to_float()
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--frames="):
			_max_frames = arg.trim_prefix("--frames=").to_int()
	var scene_path := str(GameConfig.region(region_id).get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("região sem cena: %s" % region_id)
		return
	var world := (load(scene_path) as PackedScene).instantiate()
	add_child(world)
	var amb := AmbienceDirector.new()
	add_child(amb)
	amb.apply(world, region_id)
	var target := Vector3(at.x, 1.0, at.y)
	var cfg: Dictionary = {"fov_deg": GameConfig.get_f("camera", "fov_deg"), "pitch_deg": GameConfig.get_f("camera", "pitch_deg"), "initial_yaw_deg": GameConfig.get_f("camera", "initial_yaw_deg")}
	var cam := Camera3D.new()
	cam.fov = float(cfg.get("fov_deg", 40.0))
	add_child(cam)
	var pitch := deg_to_rad(float(cfg.get("pitch_deg", 45.0)))
	var yaw := deg_to_rad(float(cfg.get("initial_yaw_deg", 45.0)))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at_from_position(target + off, target, Vector3.UP)
	cam.current = true
	var marker := Node3D.new() # as partículas de ambiente seguem este ponto
	add_child(marker)
	marker.position = target
	amb.follow = marker


func _process(_delta: float) -> void:
	_frames += 1
	if _shot != "" and _frames == _max_frames:
		get_viewport().get_texture().get_image().save_png(_shot)
		print("[region_preview] ", _shot)
		get_tree().quit()
