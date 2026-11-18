class_name InputSetup
extends RefCounted

## Garante que todas as ações de input do FPS estejam configuradas no InputMap.
## Serve como garantia de compatibilidade caso haja variações de versão no Godot 4.x.
static func ensure_inputs() -> void:
	var key_bindings: Dictionary = {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"ui_cancel": KEY_ESCAPE,
		"restart": KEY_F3,
		"reload": KEY_R,
		"scoreboard": KEY_TAB,
		"buy_menu": KEY_CTRL,
		"throw_grenade": KEY_F,
		"slot_1": KEY_1,
		"slot_2": KEY_2,
		"slot_3": KEY_3
	}
	
	for action: String in key_bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		# Se for throw_grenade, garante atualização para a tecla F
		if action == "throw_grenade":
			InputMap.action_erase_events(action)
			var event := InputEventKey.new()
			event.physical_keycode = KEY_F
			InputMap.action_add_event(action, event)
		elif InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.physical_keycode = key_bindings[action]
			InputMap.action_add_event(action, event)
			
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	if InputMap.action_get_events("shoot").is_empty():
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", mouse_event)
