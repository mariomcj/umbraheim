extends SceneTree
## Executor mínimo de testes, sem dependências externas.
## Uso: godot --headless --path . -s res://tests/run_tests.gd
## Cada suíte é um script com métodos test_*() que retornam "" (ok) ou a mensagem de falha.
## (GUT/gdUnit4 podem substituir este executor quando as suítes crescerem — ver DECISOES.md.)

const SUITES: PackedStringArray = [
	"res://tests/test_snapshot_codec.gd",
	"res://tests/test_config_files.gd",
	"res://tests/test_journal.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_items.gd",
	"res://tests/test_refine.gd",
	"res://tests/test_city.gd",
	"res://tests/test_persistence.gd",
	"res://tests/test_social.gd",
	"res://tests/test_world.gd",
	"res://tests/test_guilds.gd",
	"res://tests/test_classes.gd",
	"res://tests/test_events.gd",
	"res://tests/test_endgame.gd",
]


func _initialize() -> void:
	var passed := 0
	var failed := 0
	for path in SUITES:
		var suite: Object = (load(path) as GDScript).new()
		for method in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var result: String = suite.call(method_name)
			if result.is_empty():
				passed += 1
				print("  ok    %s::%s" % [path.get_file(), method_name])
			else:
				failed += 1
				print("  FALHA %s::%s — %s" % [path.get_file(), method_name, result])
	print("Resultado: %d ok, %d falha(s)" % [passed, failed])
	quit(1 if failed > 0 else 0)
