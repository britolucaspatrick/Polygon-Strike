class_name TouchControls
extends Control

## Referências aos nós principais
var player: CharacterBody3D = null
var hud: CanvasLayer = null

## Estado de exibição e controle
var is_active: bool = false
var force_mobile_test: bool = false

## Joystick Virtual (Lado Esquerdo)
var joystick_touch_index: int = -1
var joystick_center: Vector2 = Vector2(170, 550)
var joystick_knob_pos: Vector2 = Vector2(170, 550)
var joystick_radius: float = 65.0
var joystick_deadzone: float = 0.15
var joystick_output: Vector2 = Vector2.ZERO
var is_joystick_active: bool = false

## Zona de Rotação de Câmera / Mira (Lado Direito)
var look_touch_index: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

## Lista de Botões Touch
var touch_buttons: Array[Dictionary] = []

func _ready() -> void:
	# Previne que o controle bloqueie cliques normais da UI quando não tocado
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Detecta se está em dispositivo mobile com touchscreen nativo
	var is_mobile_device: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	set_active(is_mobile_device or force_mobile_test)
	
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()

func set_active(active: bool) -> void:
	is_active = active
	visible = is_active
	set_process_input(is_active)
	queue_redraw()

func _ensure_references() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not hud:
		hud = get_parent() as CanvasLayer
		if not hud and get_tree().current_scene:
			hud = get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer

## Recalcula as posições dos botões e do joystick de acordo com a resolução da tela
func _update_layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
		
	# Joystick ancorado na parte inferior esquerda
	joystick_center = Vector2(clamp(vp_size.x * 0.14, 120.0, 200.0), vp_size.y - clamp(vp_size.y * 0.24, 120.0, 190.0))
	if not is_joystick_active:
		joystick_knob_pos = joystick_center
		
	# Lista de Botões de Ação Dinâmicos
	touch_buttons = [
		{
			"id": "shoot",
			"pos": Vector2(vp_size.x - 110, vp_size.y - 130),
			"radius": 46.0,
			"color": Color(1.0, 0.28, 0.24, 0.65),
			"active_color": Color(1.0, 0.45, 0.4, 0.95),
			"icon": "🎯",
			"label": "TIRO",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "aim",
			"pos": Vector2(vp_size.x - 205, vp_size.y - 110),
			"radius": 34.0,
			"color": Color(0.2, 0.8, 1.0, 0.6),
			"active_color": Color(0.3, 0.95, 1.0, 0.95),
			"icon": "🔍",
			"label": "MIRA",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "jump",
			"pos": Vector2(vp_size.x - 65, vp_size.y - 235),
			"radius": 34.0,
			"color": Color(0.3, 0.9, 0.4, 0.6),
			"active_color": Color(0.4, 1.0, 0.5, 0.95),
			"icon": "🦘",
			"label": "PULO",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "reload",
			"pos": Vector2(vp_size.x - 150, vp_size.y - 215),
			"radius": 30.0,
			"color": Color(1.0, 0.85, 0.25, 0.6),
			"active_color": Color(1.0, 0.95, 0.4, 0.95),
			"icon": "🔄",
			"label": "RECARGA",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "grenade",
			"pos": Vector2(vp_size.x - 225, vp_size.y - 195),
			"radius": 30.0,
			"color": Color(1.0, 0.5, 0.2, 0.6),
			"active_color": Color(1.0, 0.7, 0.35, 0.95),
			"icon": "💣",
			"label": "GRANADA",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "weapon",
			"pos": Vector2(vp_size.x - 110, vp_size.y - 305),
			"radius": 30.0,
			"color": Color(0.85, 0.45, 1.0, 0.6),
			"active_color": Color(0.95, 0.65, 1.0, 0.95),
			"icon": "🔫",
			"label": "ARMA",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "shop",
			"pos": Vector2(65, 120),
			"radius": 28.0,
			"color": Color(0.2, 0.95, 0.5, 0.65),
			"active_color": Color(0.4, 1.0, 0.7, 0.95),
			"icon": "🛒",
			"label": "LOJA",
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "scoreboard",
			"pos": Vector2(135, 120),
			"radius": 28.0,
			"color": Color(0.35, 0.65, 1.0, 0.65),
			"active_color": Color(0.55, 0.8, 1.0, 0.95),
			"icon": "📊",
			"label": "TAB",
			"pressed": false,
			"touch_index": -1
		}
	]
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_active:
		return
	_ensure_references()
	
	# 1. Trata Toques de Tela (Mobile ou emulador)
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position, event.relative)
		
	# 2. Permite testar no PC com cliques do mouse se force_mobile_test estiver ativo
	elif force_mobile_test:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(999, event.position, event.pressed)
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_drag(999, event.position, event.relative)

func _handle_touch(touch_idx: int, pos: Vector2, is_down: bool) -> void:
	var vp_width: float = get_viewport_rect().size.x
	var is_left_half: bool = (pos.x < vp_width * 0.45)
	
	if is_down:
		# A. Verifica primeiro se tocou em algum dos botões de ação da interface
		for btn in touch_buttons:
			var dist = pos.distance_to(btn["pos"])
			if dist <= (btn["radius"] * 1.25):
				btn["pressed"] = true
				btn["touch_index"] = touch_idx
				_execute_button_action(btn["id"], true)
				queue_redraw()
				return
				
		# B. Se tocou no lado esquerdo da tela: ativa ou reposiciona o Joystick
		if is_left_half and joystick_touch_index == -1:
			joystick_touch_index = touch_idx
			is_joystick_active = true
			joystick_center = pos
			joystick_knob_pos = pos
			queue_redraw()
			return
			
		# C. Se tocou no lado direito da tela (fora dos botões): inicia controle de câmera/mira
		elif not is_left_half and look_touch_index == -1:
			look_touch_index = touch_idx
			last_look_pos = pos
			return
			
	else:
		# Soltou o dedo
		# A. Verifica se liberou algum botão
		for btn in touch_buttons:
			if btn["touch_index"] == touch_idx:
				btn["pressed"] = false
				btn["touch_index"] = -1
				_execute_button_action(btn["id"], false)
				queue_redraw()
				
		# B. Verifica se liberou o Joystick
		if touch_idx == joystick_touch_index:
			joystick_touch_index = -1
			is_joystick_active = false
			joystick_output = Vector2.ZERO
			joystick_knob_pos = joystick_center
			if player:
				player.touch_move_vector = Vector2.ZERO
			queue_redraw()
			
		# C. Verifica se liberou o controle de Câmera/Mira
		if touch_idx == look_touch_index:
			look_touch_index = -1

func _handle_drag(touch_idx: int, pos: Vector2, relative_motion: Vector2) -> void:
	# A. Movimento do Joystick Virtual
	if touch_idx == joystick_touch_index:
		var offset: Vector2 = pos - joystick_center
		var dist: float = offset.length()
		if dist > joystick_radius:
			offset = offset.normalized() * joystick_radius
			
		joystick_knob_pos = joystick_center + offset
		var norm_vec: Vector2 = offset / joystick_radius
		
		if norm_vec.length() < joystick_deadzone:
			joystick_output = Vector2.ZERO
		else:
			# X = Strafe (esquerda/direita), Y = Avançar/Recuar
			joystick_output = Vector2(norm_vec.x, norm_vec.y)
			
		if player:
			player.touch_move_vector = joystick_output
		queue_redraw()
		
	# B. Rotação suave da Câmera (Arrastar o dedo no lado direito da tela)
	elif touch_idx == look_touch_index:
		var delta_look: Vector2 = pos - last_look_pos
		last_look_pos = pos
		if player and player.has_method("apply_touch_look"):
			player.apply_touch_look(delta_look)

## Executa ações imediatas de cada botão touch
func _execute_button_action(action_id: String, is_pressed: bool) -> void:
	if not player:
		return
		
	match action_id:
		"shoot":
			player.touch_shoot_held = is_pressed
			if is_pressed:
				player.touch_just_shot = true
				
		"aim":
			if is_pressed and player.has_method("toggle_touch_aim"):
				player.toggle_touch_aim()
				
		"jump":
			if is_pressed and player.has_method("trigger_touch_jump"):
				player.trigger_touch_jump()
				
		"reload":
			if is_pressed and player.has_method("_reload"):
				player._reload()
				
		"grenade":
			if is_pressed and player.has_method("_throw_grenade"):
				player._throw_grenade()
				
		"weapon":
			if is_pressed and player.has_method("_cycle_weapon"):
				player._cycle_weapon(1)
				
		"shop":
			if is_pressed and hud and "buy_menu_panel" in hud and hud.buy_menu_panel:
				var new_vis = not hud.buy_menu_panel.visible
				hud.set_buy_menu_visible(new_vis)
				
		"scoreboard":
			if is_pressed and hud and "scoreboard_panel" in hud and hud.scoreboard_panel:
				var new_vis = not hud.scoreboard_panel.visible
				hud.set_scoreboard_visible(new_vis)

## Desenha o Joystick Virtual e os Botões Touch usando primitivas nativas 2D
func _draw() -> void:
	if not is_active:
		return
		
	# 1. Desenha o Joystick Virtual (Lado Esquerdo)
	var base_col = Color(1.0, 1.0, 1.0, 0.15) if not is_joystick_active else Color(0.2, 0.9, 1.0, 0.25)
	var ring_col = Color(1.0, 1.0, 1.0, 0.4) if not is_joystick_active else Color(0.3, 1.0, 1.0, 0.75)
	
	draw_circle(joystick_center, joystick_radius, base_col)
	draw_arc(joystick_center, joystick_radius, 0, TAU, 32, ring_col, 2.5)
	
	# Indicador de Sprint no topo do joystick
	draw_arc(joystick_center + Vector2(0, -joystick_radius * 0.9), 12.0, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.5)
	
	# Manopla (Knob) do Joystick
	var knob_col = Color(0.25, 0.85, 1.0, 0.6) if is_joystick_active else Color(0.9, 0.9, 0.9, 0.4)
	draw_circle(joystick_knob_pos, 28.0, knob_col)
	draw_circle(joystick_knob_pos, 8.0, Color(1.0, 1.0, 1.0, 0.85))
	
	# 2. Desenha todos os Botões Touch de Ação
	var default_font := ThemeDB.fallback_font
	var font_size: int = 12
	
	for btn in touch_buttons:
		var b_pos: Vector2 = btn["pos"]
		var b_rad: float = btn["radius"]
		var is_btn_down: bool = btn["pressed"]
		
		var fill_color: Color = btn["active_color"] if is_btn_down else btn["color"]
		var border_color: Color = Color(1.0, 1.0, 1.0, 0.85) if is_btn_down else Color(1.0, 1.0, 1.0, 0.45)
		var scale_rad: float = b_rad * (1.12 if is_btn_down else 1.0)
		
		# Círculo base do botão
		draw_circle(b_pos, scale_rad, fill_color)
		draw_arc(b_pos, scale_rad, 0, TAU, 28, border_color, 2.2)
		
		# Ícone Emoji centralizado
		var icon_str: String = btn["icon"]
		draw_string(default_font, b_pos + Vector2(-10, -2), icon_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		
		# Rótulo de texto abaixo do ícone
		var label_str: String = btn["label"]
		draw_string(default_font, b_pos + Vector2(-24, 18), label_str, HORIZONTAL_ALIGNMENT_CENTER, 48, font_size, Color(1, 1, 1, 0.9))
