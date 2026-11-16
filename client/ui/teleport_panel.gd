class_name TeleportPanel
extends PanelContainer
## "Viajar" ao lado do diário aberto: lista só as regiões que já têm folha no diário
## (como pede a especificação), com nível mínimo e custo. O servidor confere tudo de novo.

var GOLD: Color = UiPalette.c("gold")

var _list: VBoxContainer
var _sheets := PackedStringArray()
var _current: String = ""


func _ready() -> void:
	theme_type_variation = &"ParchmentPanel" # o papel do diário, ao lado da página
	set_meta("no_window_fx", true) # fica preso ao diário
	custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Viajar"
	title.theme_type_variation = &"InkTitle"
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Só aparecem lugares que já estão\nnas folhas do seu diário."
	hint.theme_type_variation = &"InkLabel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiPalette.c("paper_ink", 0.65))
	box.add_child(hint)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)


func set_sheets(sheets: PackedStringArray, current_region: String) -> void:
	_sheets = sheets
	_current = current_region
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var order: Array = GameConfig.table("world")["regions"]
	for region_id: String in order:
		if not _sheets.has(region_id):
			continue
		var data := GameConfig.region(region_id)
		var b := Button.new() # entrada do diário: tinta sobre o papel, sublinhada ao passar o mouse
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UiPalette.font("lore"))
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", UiPalette.c("paper_ink"))
		b.add_theme_color_override("font_hover_color", UiPalette.c("paper_red"))
		b.add_theme_color_override("font_pressed_color", UiPalette.c("paper_red"))
		b.add_theme_color_override("font_disabled_color", UiPalette.c("paper_ink", 0.5))
		b.add_theme_constant_override("outline_size", 0)
		if region_id == _current:
			b.text = "%s  (você está aqui)" % data.get("name", region_id)
			b.disabled = true
		else:
			b.text = "%s\n   nível %d · %d Óbolos" % [data.get("name", region_id), int(data.get("level_req", 1)), int(data.get("teleport_cost", 0))]
			b.pressed.connect(Net.send_teleport.bind(region_id))
		_list.add_child(b)
