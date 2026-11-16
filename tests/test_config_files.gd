extends RefCounted
## Garante que todo arquivo de configuração existe, é JSON válido e tem as chaves usadas no código.

const REQUIRED := {
	"network": ["port", "default_server_url", "handshake_timeout_s", "connect_after_frames", "tick_rate_hz", "max_ticks_per_frame", "input_send_rate_hz", "stats_log_interval_s"],
	"journal": ["sample_distance_m", "stroke_break_distance_m", "rdp_epsilon_m", "simplify_chunk_points", "landmark_check_interval_ticks", "paper_size_px", "pencil_speed_px_s", "pencil_catchup_px", "marker_follow_sharpness", "stamp_spacing_px", "stroke_width_px", "stroke_alpha", "jitter_px", "wobble_px", "mark_size_px", "mark_stroke_duration_s", "label_chars_per_s", "label_font_px", "title_font_px", "minimap_size_px", "minimap_zoom", "full_view_height_ratio"],
	"movement": ["start_region", "player_speed_mps", "spawn_radius_m", "world_half_extent_m", "interpolation_delay_ms"],
	"camera": ["pitch_deg", "initial_yaw_deg", "fov_deg", "distance_m", "min_distance_m", "max_distance_m", "zoom_step_m", "rotate_speed_deg_s", "follow_sharpness", "look_height_m"],
	"input": ["click_move", "move_forward", "move_back", "move_left", "move_right", "camera_rotate_left", "camera_rotate_right", "zoom_in", "zoom_out", "toggle_fullscreen", "toggle_journal", "toggle_stats", "toggle_inventory", "cast_selected", "skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6", "skill_7", "skill_8", "skill_9"],
	"ui": ["damage_colors", "rarity_colors", "floating_text_rise_m", "floating_text_duration_s", "hover_radius_m", "drop_hover_radius_m", "orb_size_px", "skill_slot_px", "skill_slots", "message_log_lines", "message_log_fade_s"],
	"vfx": ["quality", "presets", "projectile_trail_particles", "impact_particles", "area_particles", "levelup_particles", "death_particles", "shake_cast", "shake_area", "shake_hit_taken"],
}


## Regiões e símbolos: toda marcação de região precisa de um símbolo que exista.
func test_regions_and_symbols() -> String:
	var symbols := ConfigLoader.load_json("res://data/journal/symbols.json")
	var movement := ConfigLoader.load_json("res://data/config/movement.json")
	var region := ConfigLoader.load_json("res://data/regions/%s.json" % movement["start_region"])
	for key in ["id", "name", "paper_px_per_m", "ink_tremor", "entrance_label", "landmarks"]:
		if not region.has(key):
			return "região sem a chave '%s'" % key
	if not symbols.has("arrow"):
		return "símbolo 'arrow' (entrada) ausente"
	var journal := ConfigLoader.load_json("res://data/config/journal.json")
	var half_paper_m := float(journal["paper_size_px"]) / float(region["paper_px_per_m"]) / 2.0
	if half_paper_m < float(movement["world_half_extent_m"]):
		return "a folha (±%.0f m) não cobre o mundo (±%.0f m)" % [half_paper_m, float(movement["world_half_extent_m"])]
	for lm: Dictionary in region["landmarks"]:
		if not symbols.has(lm["symbol"]):
			return "marco '%s' usa símbolo inexistente '%s'" % [lm["id"], lm["symbol"]]
		for stroke: Array in symbols[lm["symbol"]]:
			if stroke.size() < 2:
				return "símbolo '%s' tem traço com menos de 2 pontos" % lm["symbol"]
	return ""


func test_required_keys() -> String:
	for section: String in REQUIRED:
		var data := ConfigLoader.load_json("res://data/config/%s.json" % section)
		if data.is_empty():
			return "%s.json ausente ou inválido" % section
		for key: String in REQUIRED[section]:
			if not data.has(key):
				return "%s.json sem a chave '%s'" % [section, key]
	return ""


func test_sane_values() -> String:
	var net := ConfigLoader.load_json("res://data/config/network.json")
	var tick := int(net["tick_rate_hz"])
	if tick < 10 or tick > 20:
		return "tick_rate_hz=%d fora da faixa 10–20 Hz definida na arquitetura" % tick
	var cam := ConfigLoader.load_json("res://data/config/camera.json")
	if float(cam["min_distance_m"]) > float(cam["distance_m"]) or float(cam["distance_m"]) > float(cam["max_distance_m"]):
		return "distância inicial da câmera fora de [min, max]"
	return ""


func test_sections_match_autoload() -> String:
	var autoload_script := load("res://shared/config/game_config.gd") as GDScript
	var sections: PackedStringArray = autoload_script.get_script_constant_map()["SECTIONS"]
	for section: String in REQUIRED:
		if not section in sections:
			return "GameConfig.SECTIONS não carrega '%s'" % section
	return ""


## Áudio: todo som citado em audio.json existe e abre; toda referência a um som aponta para um som definido.
func test_audio_references() -> String:
	var cfg := ConfigLoader.load_json("res://data/config/audio.json")
	var sounds: Dictionary = cfg["sounds"]
	for sound_name: String in sounds:
		for file: Variant in (sounds[sound_name] as Dictionary)["files"]:
			var path := "res://assets/audio/" + str(file)
			if not ResourceLoader.exists(path) or not (load(path) is AudioStream):
				return "%s: não abre %s" % [sound_name, path]
	var refs: Array[String] = []
	refs.append_array((cfg["music"] as Dictionary).values().map(func(v: Variant) -> String: return str(v)))
	refs.append_array((cfg["ambient"] as Dictionary).values().map(func(v: Variant) -> String: return str(v)))
	for group: String in ["spells", "spell_overrides"]:
		for entry: Dictionary in (cfg[group] as Dictionary).values():
			refs.append_array(entry.values().map(func(v: Variant) -> String: return str(v)))
	var monsters: Dictionary = cfg["monsters"]
	var voices: Array = [monsters["default"]]
	voices.append_array((monsters["by_model"] as Dictionary).values())
	voices.append_array((monsters["by_id"] as Dictionary).values())
	for v: Dictionary in voices:
		refs.append_array(v.values().map(func(x: Variant) -> String: return str(x)))
	refs.append_array((cfg["ui"] as Dictionary).values().map(func(v: Variant) -> String: return str(v)))
	var steps: Dictionary = cfg["footsteps"]
	refs.append(str(steps["default"]))
	refs.append_array((steps["by_region"] as Dictionary).values().map(func(v: Variant) -> String: return str(v)))
	for r in refs:
		if r != "" and not sounds.has(r):
			return "som não definido: %s" % r
	var spells := GameConfig.table("spells")
	for id: String in (cfg["spell_overrides"] as Dictionary):
		if not spells.has(id):
			return "spell_overrides: magia inexistente %s" % id
	return ""
