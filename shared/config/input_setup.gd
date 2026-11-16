class_name InputSetup
extends RefCounted
## Registra as ações de input a partir de data/config/input.json.
## Formato: { "acao": { "keys": ["W", "Up"], "mouse": ["left"] } }

const MOUSE_BUTTONS := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}


static func register(config: Dictionary) -> void:
	for action: String in config:
		var spec: Dictionary = config[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key_name: Variant in spec.get("keys", []):
			var code := OS.find_keycode_from_string(str(key_name))
			if code == KEY_NONE:
				push_error("InputSetup: tecla desconhecida '%s' em '%s'" % [key_name, action])
				continue
			var key_event := InputEventKey.new()
			key_event.physical_keycode = code
			InputMap.action_add_event(action, key_event)
		for button_name: Variant in spec.get("mouse", []):
			if not MOUSE_BUTTONS.has(button_name):
				push_error("InputSetup: botão de mouse desconhecido '%s' em '%s'" % [button_name, action])
				continue
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = MOUSE_BUTTONS[button_name]
			InputMap.action_add_event(action, mouse_event)
