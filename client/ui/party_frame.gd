class_name PartyFrame
extends PanelContainer
## Quadro do grupo (lado esquerdo): nome, nível e vida de cada membro; ★ = líder.
## O próprio jogador também aparece. Botão para sair do grupo.

var GOLD: Color = UiPalette.c("gold")

class HpBar extends Control:
	var frac: float = 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.c("well"))
		var fill := UiPalette.c("blood") if frac > 0.3 else UiPalette.c("ember") # vida baixa: âmbar
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, size.y - 2)), fill)
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * frac, 1)), Color(1, 1, 1, 0.18)) # brilho de cima
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.c("iron_edge"), false, 1.0)


var my_id: int = 0
var members: Array = [] # último estado recebido
var _rows: VBoxContainer


func _ready() -> void:
	theme_type_variation = &"WindowPanel"
	position = Vector2(14, 150)
	custom_minimum_size = Vector2(190, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "GRUPO"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	box.add_child(_rows)
	var leave := Button.new()
	leave.text = "Sair do grupo"
	leave.theme_type_variation = &"GhostButton"
	leave.add_theme_font_size_override("font_size", 11)
	leave.pressed.connect(func() -> void: Net.send_party_action(Protocol.Party.LEAVE))
	box.add_child(leave)
	visible = false
	Net.party_state_received.connect(set_members)


func set_members(list: Array) -> void:
	members = list
	visible = not list.is_empty()
	# reaproveita as linhas quando só a vida mudou (o estado chega 2x por segundo)
	if _rows.get_child_count() != list.size():
		for c in _rows.get_children():
			c.queue_free()
		for i in list.size():
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 1)
			var name_label := Label.new()
			name_label.add_theme_font_size_override("font_size", 12)
			row.add_child(name_label)
			var bar := HpBar.new()
			bar.custom_minimum_size = Vector2(170, 6)
			row.add_child(bar)
			_rows.add_child(row)
	for i in list.size():
		var m: Array = list[i]
		var row := _rows.get_child(i)
		var name_label: Label = row.get_child(0)
		name_label.text = "%s%s  nv %d" % ["★ " if bool(m[4]) else "", m[1], int(m[2])]
		name_label.add_theme_color_override("font_color", UiPalette.c("void").lightened(0.3) if int(m[0]) == my_id else UiPalette.c("bone"))
		var bar: HpBar = row.get_child(1)
		bar.frac = float(m[3])
		bar.queue_redraw()
