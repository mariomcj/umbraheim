class_name IsoCameraRig
extends Node3D
## Câmera isométrica/top-down fixa (~45°) estilo MMORPG clássico.
## Segue o alvo com suavização, zoom limitado (roda do mouse) e rotação opcional (Q/E).
## Hierarquia: CameraRig (yaw, posição do alvo) -> Camera3D (pitch, distância).

var target: Node3D

var _yaw: float
var _pitch: float
var _distance: float
var _min_distance: float
var _max_distance: float
var _zoom_step: float
var _rotate_speed: float
var _follow_sharpness: float
var _look_height: float

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_pitch = deg_to_rad(GameConfig.get_f("camera", "pitch_deg"))
	_yaw = deg_to_rad(GameConfig.get_f("camera", "initial_yaw_deg"))
	_distance = GameConfig.get_f("camera", "distance_m")
	_min_distance = GameConfig.get_f("camera", "min_distance_m")
	_max_distance = GameConfig.get_f("camera", "max_distance_m")
	_zoom_step = GameConfig.get_f("camera", "zoom_step_m")
	_rotate_speed = deg_to_rad(GameConfig.get_f("camera", "rotate_speed_deg_s"))
	_follow_sharpness = GameConfig.get_f("camera", "follow_sharpness")
	_look_height = GameConfig.get_f("camera", "look_height_m")
	_camera.fov = GameConfig.get_f("camera", "fov_deg")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera-distance="): # debug (capturas de tela)
			_distance = arg.trim_prefix("--camera-distance=").to_float()
	_apply()


func yaw() -> float:
	return _yaw


func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position + Vector3.UP * _look_height


func _process(delta: float) -> void:
	if not get_viewport().gui_get_focus_owner() is LineEdit: # digitando no chat: Q/E não giram
		_yaw += Input.get_axis("camera_rotate_left", "camera_rotate_right") * _rotate_speed * delta
	if target != null:
		var goal := target.global_position + Vector3.UP * _look_height
		global_position = global_position.lerp(goal, 1.0 - exp(-_follow_sharpness * delta))
	_apply()
	_apply_shake(delta)


var _trauma: float = 0.0


## Tremida de câmera: soma "trauma" que decai; o deslocamento é proporcional ao quadrado.
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	var k := _trauma * _trauma
	var t := Time.get_ticks_msec() * 0.05
	_camera.h_offset = sin(t * 1.7) * 0.35 * k
	_camera.v_offset = sin(t * 2.3 + 1.1) * 0.35 * k


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_distance = maxf(_min_distance, _distance - _zoom_step)
	elif event.is_action_pressed("zoom_out"):
		_distance = minf(_max_distance, _distance + _zoom_step)


func _apply() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	_camera.position = Vector3(0.0, sin(_pitch) * _distance, cos(_pitch) * _distance)
	_camera.rotation = Vector3(-_pitch, 0.0, 0.0)
