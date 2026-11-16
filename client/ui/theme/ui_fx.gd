class_name UiFx
extends Node
## Comportamento comum das janelas (parte C da docs/design/PROPOSTA_UI.md), sem mexer em cada uma:
## toda PanelContainer com a variação WindowPanel ganha animação ao abrir (escala e opacidade, ui.json ->
## theme.anim), som de abrir e fechar, e pode ser arrastada pela faixa do título. Botões "×" viram o
## fechar em losango (variação CloseButton). Só no cliente gráfico.

var sound: SoundDirector
var _drag: Control
var _drag_offset := Vector2.ZERO
var _hooked: Dictionary = {} # instance_id -> true


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is PanelContainer or node is Button:
		_hook.call_deferred(node) # a variação é definida no _ready da janela, depois do node_added


func _hook(node: Node) -> void:
	if not is_instance_valid(node) or _hooked.has(node.get_instance_id()):
		return
	if node is Button:
		var b := node as Button
		if b.text == "×" and b.theme_type_variation == &"":
			b.theme_type_variation = &"CloseButton"
			b.flat = false
		return
	var w := node as PanelContainer
	if not w.theme_type_variation in [&"WindowPanel", &"ParchmentPanel"] or w.get_parent() is Container or w.has_meta("no_window_fx"):
		return # só janelas soltas (dentro de um container o layout manda; no_window_fx = painel fixo de tela)
	_hooked[w.get_instance_id()] = true
	w.visibility_changed.connect(_on_visibility.bind(w))
	w.gui_input.connect(_on_window_input.bind(w))


func _on_visibility(w: PanelContainer) -> void:
	var anim := UiPalette.theme_cfg().get("anim", {}) as Dictionary
	if w.visible:
		w.pivot_offset = w.size * 0.5
		w.scale = Vector2.ONE * float(anim.get("open_scale", 0.96))
		w.modulate.a = 0.0
		var tw := w.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(w, "scale", Vector2.ONE, float(anim.get("open_s", 0.14)))
		tw.tween_property(w, "modulate:a", 1.0, float(anim.get("open_s", 0.14)))
		_play("open")
	else:
		w.scale = Vector2.ONE
		w.modulate.a = 1.0
		_play("close")


## Arrastar pela faixa do título (os rótulos não pegam o mouse; os botões, sim).
func _on_window_input(event: InputEvent, w: PanelContainer) -> void:
	var drag_px := float(UiPalette.theme_cfg().get("frame", {}).get("drag_strip_px", 40))
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.position.y <= drag_px:
			_drag = w
			_drag_offset = w.get_global_mouse_position() - w.global_position
			w.accept_event()
		elif not mb.pressed and _drag == w:
			_drag = null
	elif event is InputEventMouseMotion and _drag == w:
		var vp := w.get_viewport_rect().size
		var pos := w.get_global_mouse_position() - _drag_offset
		w.global_position = pos.clamp(Vector2(-w.size.x + 60.0, 0.0), vp - Vector2(60.0, 30.0)) # nunca some da tela
		w.accept_event()


func _play(event: String) -> void:
	if sound != null:
		sound.ui(event)
