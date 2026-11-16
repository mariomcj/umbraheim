class_name DebugOverlay
extends CanvasLayer
## Overlay de debug: FPS, estado da conexão, jogadores visíveis, tick do servidor e as teclas.
## Escondido por padrão; F3 mostra e esconde (--debug-hud começa visível).

const REFRESH_S := 0.25

var status_text: String = ""
var players_visible: int = 0
var last_tick: int = 0

var _label: Label
var _timer: float = 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	visible = "--debug-hud" in OS.get_cmdline_user_args()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_S
	_label.text = "FPS %d | %s\nEntidades visíveis: %d | tick %d\nClique: andar/atacar/pegar · 1-3: magias · botão direito: magia selecionada\nWASD: andar · Q/E: girar · roda: zoom · J: diário · M: minimapa · C: atributos · I: inventário · G: guilda · F: amigos · K: maestria · F10: tela cheia" % [
		Engine.get_frames_per_second(), status_text, players_visible, last_tick]
