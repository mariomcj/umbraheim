class_name Hud
extends CanvasLayer
## HUD do jogo (ver GUIA_DE_ARTE): orbe de vida (esquerda) e de mana (direita) colados
## à barra de skills 1–9, barra de XP embaixo, quadro do alvo no topo, log de mensagens,
## janela de atributos (C) e aviso de morte. Só exibe o que o servidor informa.

signal add_stat_pressed(stat_index: int, amount: int)
signal reset_pressed
signal mastery_pressed
## Botões de sistema (losangos à direita da barra): nome da ação de entrada (ex.: toggle_inventory).
signal system_pressed(action: StringName)

const ORB_SHADER := preload("res://assets/shaders/ui_orb.gdshader")
var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")
var FRAME_BG: Color = UiPalette.c("ink", 0.92)
const STAT_NAMES: PackedStringArray = ["Força", "Agilidade", "Vitalidade", "Energia"]


## Orbe com líquido (shader) e o valor escrito no centro.
class Orb extends Control:
	var material_orb: ShaderMaterial
	var label: Label

	func setup(color: Color, side: float) -> void:
		custom_minimum_size = Vector2(side, side)
		size = Vector2(side, side)
		var rect := ColorRect.new()
		material_orb = ShaderMaterial.new()
		material_orb.shader = ORB_SHADER
		material_orb.set_shader_parameter("liquid", color)
		rect.material = material_orb
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		label = Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", UiPalette.c("bone"))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		add_child(label)

	func set_value(value: int, max_value: int) -> void:
		material_orb.set_shader_parameter("fill", clampf(float(value) / maxf(1.0, float(max_value)), 0.0, 1.0))
		label.text = "%d / %d" % [value, max_value]


## Slot de skill desenhado à mão: moldura, runa colorida, tecla, recarga em "pizza".
class SkillSlot extends Control:
	var key_text: String = ""
	var spell_name: String = ""
	var icon: String = "" # UiIcons (ui.json -> theme.icons); vazio = inicial da magia
	var color: Color = Color(0.3, 0.3, 0.3)
	var empty: bool = true
	var selected: bool = false
	var no_mana: bool = false
	var locked: bool = false # magia ainda não aprendida
	var cooldown_frac: float = 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var shape := Hud.chamfer(r, 4.0)
		draw_colored_polygon(shape, UiPalette.c("well", 0.92))
		draw_line(Vector2(4, 1), Vector2(size.x - 4, 1), Color(0, 0, 0, 0.6), 2.0) # rebaixo: sombra no topo
		if not empty:
			var c := r.get_center()
			var radius := size.x * 0.32
			draw_circle(c, radius, color.darkened(0.55))
			draw_arc(c, radius, 0.0, TAU, 24, color.lightened(0.2), 2.0, true)
			if UiIcons.has(icon):
				UiIcons.draw(self, icon, c, radius * 0.72, color.lightened(0.45))
			else:
				var glyph := spell_name.left(1)
				var font := UiPalette.font("title")
				var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
				draw_string(font, c + Vector2(-gw * 0.5, 7), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color.lightened(0.5))
			if locked:
				draw_rect(r, Color(0.02, 0.02, 0.02, 0.72))
				draw_rect(Rect2(c + Vector2(-6, -1), Vector2(12, 9)), Color(0.55, 0.5, 0.42))
				draw_arc(c + Vector2(0, -1), 4.5, PI, TAU, 10, Color(0.55, 0.5, 0.42), 2.0)
			elif no_mana:
				draw_rect(r, Color(0.05, 0.1, 0.35, 0.45))
			if cooldown_frac > 0.0:
				var pts := PackedVector2Array([c])
				var steps := 24
				for i in steps + 1:
					var a := -PI / 2.0 + TAU * cooldown_frac * float(i) / steps
					pts.append(c + Vector2(cos(a), sin(a)) * size.x)
				draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var closed := shape.duplicate()
		closed.append(shape[0])
		if selected: # brilho na cor da magia por fora e filete dourado
			draw_polyline(closed, Color(color.lightened(0.3), 0.35), 5.0, true)
			draw_polyline(closed, UiPalette.c("gold"), 2.0, true)
		elif not empty:
			draw_polyline(closed, UiPalette.c("gold_dim"), 1.5, true)
		else: # vaga vazia: só o rebaixo, sem filete forte
			draw_polyline(closed, UiPalette.c("iron_edge", 0.7), 1.0, true)
		# tecla num losango pequeno no canto
		var kc := Vector2(9, 9)
		var kd := PackedVector2Array([kc + Vector2(0, -7), kc + Vector2(7, 0), kc + Vector2(0, 7), kc + Vector2(-7, 0)])
		draw_colored_polygon(kd, UiPalette.c("ink", 0.95))
		kd.append(kd[0])
		draw_polyline(kd, UiPalette.c("gold_dim") if not empty else UiPalette.c("iron_edge"), 1.0, true)
		var kf := UiPalette.font("body_bold")
		var kw := kf.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(kf, kc + Vector2(-kw * 0.5, 4), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiPalette.c("bone") if not empty else UiPalette.c("bone_dim", 0.6))


class XpBar extends Control:
	var frac: float = 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.c("well", 0.95))
		var w := (size.x - 2) * frac
		var gold := UiPalette.c("gold")
		draw_rect(Rect2(Vector2(1, 1), Vector2(w, size.y - 2)), gold.darkened(0.25))
		draw_rect(Rect2(Vector2(1, 1), Vector2(w, 2)), Color(gold.lightened(0.3), 0.6)) # luz no topo
		if frac > 0.0 and frac < 1.0: # brilho na ponta que avança
			for i in 4:
				draw_rect(Rect2(Vector2(1 + w - 2 - i * 3, 0), Vector2(3, size.y)), Color(1.0, 0.85, 0.5, 0.5 - i * 0.12))
		for i in range(1, 10):
			var x := size.x * i / 10.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.7), 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.c("iron_edge"), false, 1.0)


## Anel de metal em volta do orbe: aro escuro, filete dourado e quatro cravos.
class OrbRing extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_arc(c, r - 4.0, 0.0, TAU, 64, UiPalette.c("iron_top"), 8.0, true)
		draw_arc(c, r - 0.5, 0.0, TAU, 64, UiPalette.c("iron_edge"), 1.5, true)
		draw_arc(c, r - 8.0, 0.0, TAU, 64, UiPalette.c("gold_dim"), 1.5, true)
		draw_arc(c, r - 2.5, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.08), 2.0, true) # reflexo no aro
		for i in 4:
			var a := PI * 0.25 + i * PI * 0.5
			var p := c + Vector2(cos(a), sin(a)) * (r - 4.0)
			draw_circle(p, 3.2, UiPalette.c("gold_dim"))
			draw_circle(p - Vector2(0.8, 0.8), 1.3, Color(1, 0.95, 0.8, 0.5))


## Retângulo com cantos chanfrados (vagas de magia).
static func chamfer(r: Rect2, c: float) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	return PackedVector2Array([Vector2(a.x + c, a.y), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c), Vector2(b.x, b.y - c),
		Vector2(b.x - c, b.y), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), Vector2(a.x, a.y + c)])


class TargetBar extends Control:
	var frac: float = 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.02, 0.02))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2)), Color(0.72, 0.1, 0.08))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.3, 0.2), false, 1.0)


var spells: Array[Dictionary] = []
var state := PackedInt64Array()

var _hp_orb: Orb
var _mana_orb: Orb
var _slots: Array[SkillSlot] = []
var _slot_spell := PackedInt32Array() # slot visual (0..8) -> índice da magia ou -1
var _cooldowns: Dictionary = {} # índice da magia -> [fim_ms, total_ms]
var _selected_index: int = -1
var _xp_bar: XpBar
var _level_label: DiamondButton
var _target_panel: PanelContainer
var _target_name: Label
var _target_bar: TargetBar
## Chat e mensagens do sistema (substituiu o registro de mensagens na Fase 3).
var chat: ChatBox
## Avisos: placa de evento, título de área, toasts e tela de morte.
var notices: Notices
var _stats: PanelContainer
var _stats_labels: Dictionary = {}
var _stat_buttons: Array[Button] = []
var _hp_potions: DiamondButton
var _mana_potions: DiamondButton
var _system_row: HBoxContainer
var _location_title: Label
var _location_sub: Label
var class_title: String = ""
var class_id: String = ""
var _reset_button: Button
var _confirm_reset: bool = false
var damage_label: String = "Dano mágico"
var _buff_row: HBoxContainer
var _buffs: Array = [] # [[nome, fim em ms, Label]]
var _quest_label: Label
var _events_panel: PanelContainer
var _events_rows: VBoxContainer
var _events_open: bool = true
var _events_toggle: Button
var _event_rows: Array = [] # último calendário recebido
var _event_rows_at: int = 0 # quando chegou (ms)
var _event_box: VBoxContainer
var _event_title: Label
var _event_line: Label
var _event_timer: Label
var _event_extra: Label
var _event_left_s: float = 0.0
var _event_at: int = 0


func _ready() -> void:
	layer = 5
	notices = Notices.new() # primeiro: fica atrás das barras e janelas
	add_child(notices)
	_build_bottom_bar()
	_build_target_frame()
	chat = ChatBox.new()
	add_child(chat)
	_build_stats_window()
	_buff_row = HBoxContainer.new()
	_buff_row.anchor_left = 0.5
	_buff_row.anchor_right = 0.5
	_buff_row.anchor_top = 1.0
	_buff_row.anchor_bottom = 1.0
	_buff_row.offset_top = -150.0
	_buff_row.offset_bottom = -128.0
	_buff_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buff_row.add_theme_constant_override("separation", 10)
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buff_row)
	_quest_label = _label("", 12, GOLD)
	_quest_label.anchor_left = 1.0
	_quest_label.anchor_right = 1.0
	_quest_label.offset_left = -300.0
	_quest_label.offset_right = -18.0
	_quest_label.offset_top = 262.0
	_quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quest_label.add_theme_constant_override("outline_size", 5)
	_quest_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_quest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quest_label)
	_build_events_panel()
	_build_location()
	_event_box = VBoxContainer.new()
	_event_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_box.offset_top = 112.0 # abaixo do quadro do alvo e do texto de depuração
	_event_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_box.visible = false
	add_child(_event_box)
	_event_title = _label("", 18, GOLD)
	_event_line = _label("", 14, PARCHMENT)
	_event_timer = _label("", 14, Color(1.0, 0.75, 0.45))
	_event_extra = _label("", 12, Color(0.85, 0.8, 0.65))
	for l: Label in [_event_title, _event_line, _event_extra, _event_timer]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_event_box.add_child(l)


## Classe do personagem: título (com a evolução) e o nome do dano na janela de atributos.
func set_class_info(title: String, dmg_label: String, cls: String = "") -> void:
	class_title = title
	class_id = cls
	damage_label = dmg_label
	_refresh_stats()


## Bônus temporários ativos: [[nome, segundos], ...] (contagem regressiva acima da barra).
func set_buffs(list: Array) -> void:
	for b: Array in _buffs:
		(b[2] as Label).queue_free()
	_buffs.clear()
	var now := Time.get_ticks_msec()
	for b: Array in list:
		var l := _label("", 12, Color(1.0, 0.85, 0.45))
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_buff_row.add_child(l)
		_buffs.append([str(b[0]), now + float(b[1]) * 1000.0, l])


## Calendário dos eventos: [[id, nome, estado, segundos], ...] (contagem regressiva local).
func set_event_schedule(rows: Array) -> void:
	_event_rows = rows
	_event_rows_at = Time.get_ticks_msec()


## Painel do evento em que o jogador está ({} = fora).
func set_event_state(state: Dictionary) -> void:
	_event_box.visible = not state.is_empty()
	if state.is_empty():
		return
	_event_title.text = str(state["title"])
	_event_line.text = str(state["line"])
	_event_extra.text = str(state.get("extra", ""))
	_event_extra.visible = _event_extra.text != ""
	_event_extra.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if _event_extra.text.begins_with("FORA") else Color(0.85, 0.8, 0.65))
	_event_line.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if bool(state.get("won", false)) else PARCHMENT)
	_event_left_s = float(state["left_s"])
	_event_at = Time.get_ticks_msec()
	_event_timer.visible = not bool(state.get("done", false))


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	return "%d:%02d" % [s / 60, s % 60] if s < 3600 else "%dh%02d" % [s / 3600, (s % 3600) / 60]


## Rastreador da missão ativa (canto direito, abaixo do minimapa).
func set_quest_text(text: String) -> void:
	_quest_label.text = text


func setup_spells(spell_list: Array[Dictionary]) -> void:
	spells = spell_list
	_slot_spell.resize(_slots.size())
	_slot_spell.fill(-1)
	_selected_index = -1
	for s in _slots: # troca de classe: limpa as teclas antes
		s.empty = true
		s.spell_name = ""
		s.icon = ""
		s.tooltip_text = ""
		s.color = Color(0.3, 0.3, 0.3)
		s.queue_redraw()
	for i in spells.size():
		var slot := int(spells[i]["slot"])
		if slot >= 1 and slot <= _slots.size():
			_slot_spell[slot - 1] = i
			var s := _slots[slot - 1]
			s.empty = false
			s.spell_name = str(spells[i]["name"])
			s.icon = UiIcons.for_spell(spells[i])
			s.color = GameConfig.color_of(spells[i].get("color"))
			s.tooltip_text = "%s — %d de mana" % [spells[i]["name"], int(spells[i]["mana_cost"])]
	if _selected_index < 0:
		set_selected(_slot_spell[0])


func set_selected(index: int) -> void:
	_selected_index = index
	for i in _slots.size():
		_slots[i].selected = _slot_spell[i] == index and index >= 0
		_slots[i].queue_redraw()


func selected_index() -> int:
	return _selected_index


func on_cooldown(index: int, seconds: float) -> void:
	var now := Time.get_ticks_msec()
	_cooldowns[index] = [now + seconds * 1000.0, seconds * 1000.0]


func set_state(s: PackedInt64Array) -> void:
	if s.size() != Protocol.PS.COUNT:
		return
	state = s
	_hp_orb.set_value(s[Protocol.PS.HP], s[Protocol.PS.HP_MAX])
	_mana_orb.set_value(s[Protocol.PS.MANA], s[Protocol.PS.MANA_MAX])
	var need := s[Protocol.PS.XP_NEXT]
	_xp_bar.frac = float(s[Protocol.PS.XP]) / float(need) if need > 0 else 1.0
	_xp_bar.queue_redraw()
	_level_label.glyph = str(s[Protocol.PS.LEVEL])
	_level_label.tooltip_text = "Nível %d · experiência %d / %d" % [s[Protocol.PS.LEVEL], s[Protocol.PS.XP], need]
	var learned := s[Protocol.PS.SPELLS]
	for i in _slots.size():
		var idx := _slot_spell[i] if i < _slot_spell.size() else -1
		if idx >= 0:
			var locked := (learned & (1 << idx)) == 0
			if _slots[i].locked != locked:
				_slots[i].locked = locked
				_slots[i].tooltip_text = ("%s — ainda não aprendida (grimório na Alquimista)" % spells[idx]["name"]) if locked \
					else ("%s — %d de mana" % [spells[idx]["name"], int(spells[idx]["mana_cost"])])
	var alive := s[Protocol.PS.ALIVE] == 1
	notices.set_death(alive, s[Protocol.PS.RESPAWN_MS])
	_refresh_stats()


func set_target(name_text: String, level: int, hp_frac: float) -> void:
	if name_text.is_empty():
		_target_panel.visible = false
		return
	_target_panel.visible = true
	_target_name.text = "%s  ·  nível %d" % [name_text, level] if level > 0 else name_text
	_target_bar.frac = hp_frac
	_target_bar.queue_redraw()


func add_message(text: String, color: Color = Color.TRANSPARENT) -> void:
	chat.add_line(text, PARCHMENT if color.a == 0.0 else color)


## Contadores de poção ao lado dos orbes (atalhos Z e X).
func set_potions(hp_count: int, mana_count: int) -> void:
	_hp_potions.badge = "×%d" % hp_count
	_mana_potions.badge = "×%d" % mana_count
	_hp_potions.dimmed = hp_count <= 0
	_mana_potions.dimmed = mana_count <= 0


## Onde o jogador está (canto superior esquerdo, fixo): região ou zona e o subtítulo.
func set_location(title: String, subtitle: String) -> void:
	_location_title.text = title
	_location_sub.text = subtitle
	_location_sub.visible = subtitle != ""


## Faixa no alto da tela ao entrar/sair de uma área (ex.: "Refúgio das Cinzas · zona segura").
func show_area(title: String, subtitle: String) -> void:
	notices.show_area(title, subtitle)


## Aviso de evento no topo (anúncios do servidor, portões que abrem).
func show_event(title: String, subtitle: String) -> void:
	notices.show_event(title, subtitle)


## Toast à direita (item obtido, missão, amigo entrou).
func show_toast(text: String, glyph: String, accent: Color) -> void:
	notices.show_toast(text, glyph, accent)


func toggle_stats() -> void:
	_stats.visible = not _stats.visible
	_refresh_stats()


func is_over_ui(screen_pos: Vector2) -> bool:
	for c: Control in [_stats, _target_panel]:
		if c.visible and c.get_global_rect().has_point(screen_pos):
			return true
	return false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _stats.visible: # "+" pulsa enquanto há pontos livres
		var pulse := 0.75 + 0.25 * sin(now / 1000.0 * 4.0)
		for b in _stat_buttons:
			b.modulate = Color(1, 1, 1, pulse) if not b.disabled else Color.WHITE
	var mana := state[Protocol.PS.MANA] if state.size() == Protocol.PS.COUNT else 0
	for i in _slots.size():
		var idx := _slot_spell[i] if i < _slot_spell.size() else -1
		if idx < 0:
			continue
		var s := _slots[i]
		var cd: Array = _cooldowns.get(idx, [0.0, 1.0])
		s.cooldown_frac = clampf((float(cd[0]) - now) / maxf(1.0, float(cd[1])), 0.0, 1.0)
		s.no_mana = mana < int(spells[idx]["mana_cost"])
		s.queue_redraw()
	for b: Array in _buffs:
		var left := (float(b[1]) - now) / 1000.0
		(b[2] as Label).text = "%s %ds" % [b[0], ceili(left)] if left > 0.0 else ""
	_events_panel.visible = not _event_rows.is_empty()
	if not _event_rows.is_empty() and _events_open:
		var passed := (now - _event_rows_at) / 1000.0
		var soon_s := float(UiPalette.theme_cfg().get("events_soon_s", 300))
		while _events_rows.get_child_count() < _event_rows.size():
			_events_rows.add_child(_event_row())
		for i in _events_rows.get_child_count():
			var row := _events_rows.get_child(i) as HBoxContainer
			row.visible = i < _event_rows.size()
			if not row.visible:
				continue
			var r: Array = _event_rows[i]
			var left := float(r[3]) - passed
			var status := row.get_child(0) as DiamondButton
			var text := row.get_child(1) as Label
			match int(r[2]):
				0:
					text.text = "%s · abre em %s" % [r[1], _clock(left)]
					status.accent = UiPalette.c("ember") if left <= soon_s else UiPalette.c("bone_dim")
					status.selected = left <= soon_s
				1:
					text.text = "%s · PORTÕES ABERTOS · %s" % [r[1], _clock(left)]
					status.accent = UiPalette.c("spectral")
					status.selected = true
				2:
					text.text = "%s · em andamento · %s" % [r[1], _clock(left)]
					status.accent = UiPalette.c("arcane")
					status.selected = true
				_:
					text.text = "%s · encerrando" % r[1]
					status.accent = UiPalette.c("bone_dim")
					status.selected = false
			text.add_theme_color_override("font_color", UiPalette.c("gold") if int(r[2]) == 1 else PARCHMENT)
	if _event_box.visible and _event_timer.visible:
		var left_e := _event_left_s - (now - _event_at) / 1000.0
		_event_timer.text = ("começa em %s" if _event_line.text == "Aguardando a largada" else "%s") % _clock(left_e)


# ---------------------------------------------------------------- construção

func _build_bottom_bar() -> void:
	var orb_px := GameConfig.get_f("ui", "orb_size_px")
	var slot_px := GameConfig.get_f("ui", "skill_slot_px")
	var count := GameConfig.get_i("ui", "skill_slots")
	var gap := 4.0
	var bar_w := count * slot_px + (count - 1) * gap
	var total_w := orb_px * 2.0 + bar_w + 24.0
	var root := Control.new()
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -total_w / 2.0
	root.offset_right = total_w / 2.0
	root.offset_top = -orb_px - 10.0
	root.offset_bottom = -6.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var plate := Panel.new() # placa de ferro do tema
	plate.position = Vector2(orb_px * 0.55, orb_px * 0.32)
	plate.size = Vector2(total_w - orb_px * 1.1, orb_px * 0.68)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)

	_hp_orb = Orb.new()
	_hp_orb.setup(Color(0.75, 0.08, 0.08), orb_px)
	_hp_orb.position = Vector2(0, 0)
	root.add_child(_hp_orb)
	_mana_orb = Orb.new()
	_mana_orb.setup(Color(0.12, 0.3, 0.85), orb_px)
	_mana_orb.position = Vector2(total_w - orb_px, 0)
	root.add_child(_mana_orb)
	var ring_pad := 6.0
	for orb_x in [0.0, total_w - orb_px]:
		var ring := OrbRing.new()
		ring.position = Vector2(orb_x - ring_pad, -ring_pad)
		ring.size = Vector2.ONE * (orb_px + ring_pad * 2.0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ring)
	# poções: losangos colados ao orbe (tecla e quantidade)
	var pot_px := 34.0
	_hp_potions = _potion_diamond("Z", UiPalette.c("blood").lightened(0.25), "Poção de vida (Z)")
	_hp_potions.position = Vector2(orb_px * 0.82, -pot_px * 0.55)
	root.add_child(_hp_potions)
	_mana_potions = _potion_diamond("X", UiPalette.c("frost"), "Poção de mana (X)")
	_mana_potions.position = Vector2(total_w - orb_px * 0.82 - pot_px, -pot_px * 0.55)
	root.add_child(_mana_potions)
	_build_system_buttons(root, total_w, orb_px)

	var x0 := orb_px + 12.0
	var y0 := orb_px * 0.32 + 8.0
	for i in count:
		var s := SkillSlot.new()
		s.key_text = str(i + 1)
		s.position = Vector2(x0 + i * (slot_px + gap), y0)
		s.size = Vector2(slot_px, slot_px)
		s.mouse_filter = Control.MOUSE_FILTER_STOP # tooltip e não deixa o clique "vazar" para o chão
		s.clip_contents = true # a "pizza" da recarga não sai do slot
		root.add_child(s)
		_slots.append(s)

	_xp_bar = XpBar.new()
	_xp_bar.position = Vector2(x0, y0 + slot_px + 5.0)
	_xp_bar.size = Vector2(bar_w, 8.0)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_xp_bar)
	# nível num losango no meio da borda de cima da placa
	var lvl_px := 34.0
	_level_label = DiamondButton.new()
	_level_label.glyph = "1"
	_level_label.accent = GOLD
	_level_label.selected = true
	_level_label.glyph_font = "body_bold"
	_level_label.custom_minimum_size = Vector2.ONE * lvl_px
	_level_label.size = _level_label.custom_minimum_size
	_level_label.position = Vector2(total_w * 0.5 - lvl_px * 0.5, orb_px * 0.32 - lvl_px * 0.62)
	root.add_child(_level_label)


func _build_target_frame() -> void:
	_target_panel = PanelContainer.new()
	_target_panel.theme_type_variation = &"WellPanel"
	_target_panel.anchor_left = 0.5
	_target_panel.anchor_right = 0.5
	_target_panel.offset_left = -150.0
	_target_panel.offset_right = 150.0
	_target_panel.offset_top = 10.0
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	_target_panel.add_child(box)
	_target_name = _label("", 15, UiPalette.c("blood").lightened(0.45))
	_target_name.add_theme_font_override("font", UiPalette.font("title"))
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_target_name)
	_target_bar = TargetBar.new()
	_target_bar.custom_minimum_size = Vector2(280, 10)
	box.add_child(_target_bar)
	_target_panel.visible = false
	add_child(_target_panel)




func _build_stats_window() -> void:
	_stats = PanelContainer.new()
	_stats.theme_type_variation = &"WindowPanel"
	_stats.position = Vector2(24, 110)
	_stats.custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_stats.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := _label("ATRIBUTOS", 16, GOLD)
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(toggle_stats)
	top.add_child(close)
	for key in ["class", "level", "xp", "points", "resets"]:
		_stats_labels[key] = _label("", 13, PARCHMENT)
		box.add_child(_stats_labels[key])
	# cabeçalho: classe em Cinzel na cor dela, nível embaixo
	_stats_labels["class"].add_theme_font_override("font", UiPalette.font("title"))
	_stats_labels["class"].add_theme_font_size_override("font_size", UiPalette.size("strong") + 1)
	_stats_labels["points"].theme_type_variation = &"ValueLabel"
	for key in ["xp", "resets"]:
		_stats_labels[key].theme_type_variation = &"HintLabel"
	box.add_child(HSeparator.new())
	for i in STAT_NAMES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := DiamondButton.new() # ícone do atributo (inicial), sem clique
		icon.glyph = STAT_NAMES[i].left(1)
		icon.custom_minimum_size = Vector2(28, 28)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var name_label := _label(STAT_NAMES[i], 14, PARCHMENT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value := _label("0", 14, GOLD)
		value.theme_type_variation = &"ValueLabel"
		value.add_theme_font_size_override("font_size", UiPalette.size("strong") + 5)
		value.custom_minimum_size = Vector2(48, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_stats_labels["stat_%d" % i] = value
		var plus := DiamondButton.new() # "+" em losango âmbar; pulsa com pontos livres (_process)
		plus.glyph = "+"
		plus.glyph_font = "body_bold"
		plus.accent = UiPalette.c("ember")
		plus.tooltip_text = "Clique: +1 · Shift+clique: +5"
		plus.custom_minimum_size = Vector2(28, 28)
		var stat_index := i
		plus.pressed.connect(func() -> void: add_stat_pressed.emit(stat_index, 5 if Input.is_key_pressed(KEY_SHIFT) else 1))
		row.add_child(plus)
		_stat_buttons.append(plus)
		box.add_child(row)
	box.add_child(HSeparator.new())
	var derived := GridContainer.new() # derivados em duas colunas
	derived.columns = 2
	derived.add_theme_constant_override("h_separation", 14)
	box.add_child(derived)
	for key in ["hp", "mana", "magic", "defense", "currency"]:
		_stats_labels[key] = _label("", 12, PARCHMENT)
		derived.add_child(_stats_labels[key])
	box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_reset_button = Button.new()
	_reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reset_button.add_theme_font_size_override("font_size", 12)
	_reset_button.pressed.connect(_on_reset_button)
	row.add_child(_reset_button)
	var mastery_button := Button.new()
	mastery_button.text = "Maestria (K)"
	mastery_button.add_theme_font_size_override("font_size", 12)
	mastery_button.pressed.connect(func() -> void: mastery_pressed.emit())
	row.add_child(mastery_button)
	_stats.visible = false
	add_child(_stats)


func _refresh_stats() -> void:
	if not _stats.visible or state.size() != Protocol.PS.COUNT:
		return
	var s := state
	_stats_labels["class"].text = class_title.to_upper()
	_stats_labels["class"].add_theme_color_override("font_color", UiPalette.class_color(class_id))
	_stats_labels["level"].text = ("Nível %d · Maestria %d" % [s[Protocol.PS.LEVEL], s[Protocol.PS.MASTER_LEVEL]]) if s[Protocol.PS.MASTER_LEVEL] > 0 else "Nível %d" % s[Protocol.PS.LEVEL]
	var rc := GameConfig.table("reset")
	var resets := int(s[Protocol.PS.RESETS])
	_stats_labels["resets"].text = "Renascimentos: %d de %d" % [resets, int(rc["max_resets"])]
	_stats_labels["resets"].visible = bool(rc["enabled"])
	var cost := MasterySystem.reset_cost(resets, rc)
	var ready := bool(rc["enabled"]) and s[Protocol.PS.LEVEL] >= int(rc["level_req"]) and resets < int(rc["max_resets"])
	_reset_button.visible = bool(rc["enabled"])
	_reset_button.disabled = not ready
	_reset_button.text = ("Confirmar: renascer?" if _confirm_reset else "Renascer (%d Óbolos)" % cost) if ready else "Renascer: nível %d" % int(rc["level_req"])
	_reset_button.tooltip_text = "Volta ao nível 1 com os atributos da classe e %d pontos por renascimento. Itens, magias e maestria ficam. Só no Refúgio." % int(rc["points_per_reset"])
	_stats_labels["xp"].text = "Experiência: %d / %d" % [s[Protocol.PS.XP], s[Protocol.PS.XP_NEXT]]
	_stats_labels["points"].text = "Pontos livres: %d" % s[Protocol.PS.POINTS]
	_stats_labels["points"].add_theme_color_override("font_color", GOLD if s[Protocol.PS.POINTS] > 0 else PARCHMENT)
	var values := [s[Protocol.PS.STR], s[Protocol.PS.AGI], s[Protocol.PS.VIT], s[Protocol.PS.ENE]]
	for i in values.size():
		_stats_labels["stat_%d" % i].text = str(values[i])
		_stat_buttons[i].disabled = s[Protocol.PS.POINTS] <= 0
		(_stat_buttons[i] as DiamondButton).dimmed = s[Protocol.PS.POINTS] <= 0
	_stats_labels["hp"].text = "Vida: %d" % s[Protocol.PS.HP_MAX]
	_stats_labels["mana"].text = "Mana: %d" % s[Protocol.PS.MANA_MAX]
	_stats_labels["magic"].text = "%s: %d ~ %d" % [damage_label, s[Protocol.PS.MAGIC_MIN], s[Protocol.PS.MAGIC_MAX]]
	_stats_labels["defense"].text = "Defesa: %d" % s[Protocol.PS.DEFENSE]
	_stats_labels["currency"].text = "%s: %d" % [GameConfig.table("drops").get("currency_name", ""), s[Protocol.PS.CURRENCY]]



func _on_reset_button() -> void:
	if not _confirm_reset: # segundo clique confirma
		_confirm_reset = true
		_refresh_stats()
		return
	_confirm_reset = false
	reset_pressed.emit()
	_refresh_stats()




func _potion_diamond(key: String, color: Color, tip: String) -> DiamondButton:
	var d := DiamondButton.new()
	d.glyph = key
	d.accent = color
	d.badge = "×0"
	d.custom_minimum_size = Vector2.ONE * 34.0
	d.size = d.custom_minimum_size
	d.tooltip_text = tip
	d.mouse_filter = Control.MOUSE_FILTER_PASS # tooltip, mas o clique segue (não usa a poção)
	return d


## Losangos de sistema à direita do orbe de mana (ui.json -> theme.system_buttons); a tecla vai no tooltip.
func _build_system_buttons(root: Control, total_w: float, orb_px: float) -> void:
	var px := float(UiPalette.theme_cfg().get("system_button_px", 34))
	_system_row = HBoxContainer.new()
	_system_row.add_theme_constant_override("separation", 2)
	_system_row.position = Vector2(total_w + 14.0, orb_px - px - 8.0)
	_system_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_system_row)
	for def: Dictionary in UiPalette.theme_cfg().get("system_buttons", []):
		var b := DiamondButton.new()
		b.glyph = str(def["glyph"])
		b.icon_id = UiIcons.for_action(str(def["action"]))
		b.custom_minimum_size = Vector2.ONE * px
		var action := StringName(str(def["action"]))
		var key := ""
		if InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty():
			key = InputMap.action_get_events(action)[0].as_text().trim_suffix(" (Physical)")
		b.tooltip_text = "%s (%s)" % [def["name"], key] if key != "" else str(def["name"])
		b.pressed.connect(func() -> void: system_pressed.emit(action))
		_system_row.add_child(b)


## Placa de eventos (direita): título que recolhe e uma linha por evento com losango de estado.
func _build_events_panel() -> void:
	_events_panel = PanelContainer.new()
	_events_panel.theme_type_variation = &"WellPanel"
	_events_panel.anchor_left = 1.0
	_events_panel.anchor_right = 1.0
	_events_panel.offset_left = -300.0
	_events_panel.offset_right = -14.0
	_events_panel.offset_top = 292.0
	_events_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_events_panel.modulate.a = 0.92
	add_child(_events_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_events_panel.add_child(box)
	_events_toggle = Button.new()
	_events_toggle.theme_type_variation = &"GhostButton"
	_events_toggle.text = "EVENTOS  −"
	_events_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_events_toggle.add_theme_font_override("font", UiPalette.font("title"))
	_events_toggle.add_theme_font_size_override("font_size", UiPalette.size("hint") + 1)
	_events_toggle.add_theme_color_override("font_color", GOLD)
	_events_toggle.pressed.connect(func() -> void:
		_events_open = not _events_open
		_events_rows.visible = _events_open
		_events_toggle.text = "EVENTOS  −" if _events_open else "EVENTOS  +"
		_events_panel.size = Vector2.ZERO)
	box.add_child(_events_toggle)
	_events_rows = VBoxContainer.new()
	_events_rows.add_theme_constant_override("separation", 1)
	box.add_child(_events_rows)
	_events_panel.visible = false


func _event_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := DiamondButton.new()
	d.custom_minimum_size = Vector2.ONE * 12.0
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)
	var l := _label("", UiPalette.size("hint") + 1, PARCHMENT)
	row.add_child(l)
	return row


## Canto superior esquerdo: onde o jogador está (antes ficava aí o texto de depuração, agora no F3).
func _build_location() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_location_title = _label("", UiPalette.size("window_title") + 2, GOLD)
	_location_title.add_theme_font_override("font", UiPalette.font("title"))
	_location_title.add_theme_constant_override("outline_size", 6)
	box.add_child(_location_title)
	_location_sub = _label("", UiPalette.size("hint") + 1, UiPalette.c("bone_dim"))
	box.add_child(_location_sub)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
