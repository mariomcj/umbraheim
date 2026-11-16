class_name QuestWindow
extends PanelContainer
## Janela do NPC de missão (Ancião Varek): texto da missão para a sua classe, etapas
## com progresso e os botões Aceitar / Entregar / Desistir. O servidor confere tudo.

var GOLD: Color = UiPalette.c("gold")
var TEXT: Color = UiPalette.c("bone")
var DIM: Color = UiPalette.c("bone_dim")
var INK: Color = UiPalette.c("paper_ink")
var INK_DIM: Color = UiPalette.c("paper_ink", 0.55)
var INK_RED: Color = UiPalette.c("paper_red")

var player_class: String = "feiticeiro"
var player_level: int = 1
var evolution: int = 0
var quests_state: Dictionary = {}

var _npc: Dictionary = {}
var _box: VBoxContainer


func _ready() -> void:
	theme_type_variation = &"ParchmentPanel" # pergaminho, como o diário
	custom_minimum_size = Vector2(460, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	visible = false


func open(npc: Dictionary) -> void:
	_npc = npc
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	_npc = {}


func set_state(state: Dictionary) -> void:
	quests_state = state
	if visible:
		_rebuild()


## Linha curta para o rastreador da HUD ("" sem missão ativa).
static func tracker_text(state: Dictionary) -> String:
	var table := GameConfig.table("quests")
	for quest_id: String in state:
		var s: Dictionary = state[quest_id]
		if bool(s.get("done", false)) or not table.has(quest_id):
			continue
		var q: Dictionary = table[quest_id]
		var steps: Array = q["steps"]
		var i := int(s.get("step", 0))
		if i >= steps.size():
			return "%s\nVolte ao %s" % [q["name"], "Ancião"]
		var step: Dictionary = steps[i]
		if str(step["type"]) == "kill":
			return "%s\n%s: %d/%d" % [q["name"], step["text"], int(s.get("count", 0)), int(step["count"])]
		return "%s\n%s" % [q["name"], step["text"]]
	return ""


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var top := HBoxContainer.new()
	_box.add_child(top)
	var who := _ink(str(_npc.get("name", "")), true)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var x := Button.new()
	x.text = "×"
	x.pressed.connect(Net.send_npc_close)
	top.add_child(x)
	var table := GameConfig.table("quests")
	for quest_id: String in _npc.get("quests", []):
		var q: Dictionary = table.get(quest_id, {})
		if q.is_empty():
			continue
		var qn := _ink(str(q["name"]), false)
		qn.add_theme_font_override("font", UiPalette.font("title"))
		qn.add_theme_font_size_override("font_size", UiPalette.size("strong"))
		_box.add_child(qn)
		var state: Dictionary = quests_state.get(quest_id, {})
		var evolves := bool(q.get("reward", {}).get("evolve", false))
		if bool(state.get("done", false)) or (evolves and evolution > 0):
			_box.add_child(_wrap(str(q.get("done_text", "Missão concluída.")), INK_DIM))
			continue
		_box.add_child(_wrap(str((q.get("intro", {}) as Dictionary).get(player_class, "")), INK))
		if evolves:
			var cls := GameConfig.table("classes/" + player_class)
			var evo: Dictionary = cls.get("evolution", {})
			_box.add_child(_wrap("Recompensa: você vira %s (+%d pontos, +%d pontos por nível e uma magia nova)." % [
				evo.get("name", "?"), int(evo.get("points_bonus", 0)), int(evo.get("points_per_level_bonus", 0))], INK_RED))
		var steps: Array = q["steps"]
		var current := int(state.get("step", -1)) if not state.is_empty() else -1
		for i in steps.size():
			var step: Dictionary = steps[i]
			var line := str(step["text"])
			if str(step["type"]) == "kill":
				line += " (%d/%d)" % [int(step["count"]) if current > i else (int(state.get("count", 0)) if current == i else 0), int(step["count"])]
			var srow := HBoxContainer.new()
			srow.add_theme_constant_override("separation", 8)
			_box.add_child(srow)
			var check := StepCheck.new() # caixinha em losango: cheia = feita, contorno forte = atual
			check.state = 2 if current > i else (1 if current == i else 0)
			srow.add_child(check)
			var sl := _ink(line, false)
			sl.add_theme_color_override("font_color", INK if current >= i else INK_DIM)
			srow.add_child(sl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_box.add_child(row)
		if state.is_empty():
			var level_req := int(q["level_req"])
			var accept := Button.new()
			accept.text = "Aceitar" if player_level >= level_req else "Aceitar (precisa de nível %d)" % level_req
			accept.disabled = player_level < level_req
			accept.pressed.connect(Net.send_quest_action.bind(Protocol.Quest.ACCEPT, quest_id))
			row.add_child(accept)
		else:
			var turn_in := Button.new()
			turn_in.text = "Entregar"
			turn_in.pressed.connect(Net.send_quest_action.bind(Protocol.Quest.TURN_IN, quest_id))
			row.add_child(turn_in)
			var give_up := Button.new()
			give_up.text = "Desistir"
			give_up.pressed.connect(Net.send_quest_action.bind(Protocol.Quest.ABANDON, quest_id))
			row.add_child(give_up)
	_recenter.call_deferred()


## No centro da tela, com o tamanho do conteúdo (o conteúdo muda a cada estado).
func _recenter() -> void:
	await get_tree().process_frame # as linhas com quebra só sabem a altura depois de um quadro
	size = Vector2.ZERO # encolhe até o tamanho mínimo do conteúdo
	position = ((get_viewport_rect().size - size) / 2.0).floor()


func _wrap(text: String, color: Color) -> Label:
	var l := _ink(text, false)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(430, 0)
	return l


## Texto em tinta sobre o pergaminho (IM Fell English).
static func _ink(text: String, title: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"InkTitle" if title else &"InkLabel"
	return l


## Caixinha em losango de uma etapa (0 = futura, 1 = atual, 2 = feita).
class StepCheck extends Control:
	var state: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(14, 18)

	func _draw() -> void:
		var ct := Vector2(7, size.y * 0.5)
		var r := 6.0
		var pts := PackedVector2Array([ct + Vector2(0, -r), ct + Vector2(r, 0), ct + Vector2(0, r), ct + Vector2(-r, 0), ct + Vector2(0, -r)])
		var ink := UiPalette.c("paper_ink")
		if state == 2:
			draw_colored_polygon(pts.slice(0, 4), UiPalette.c("paper_red"))
		draw_polyline(pts, Color(ink, 0.9 if state > 0 else 0.4), 2.0 if state == 1 else 1.2, true)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 16: # títulos e cabeçalhos em Cinzel (tema)
		l.theme_type_variation = &"TitleLabel"
	return l
