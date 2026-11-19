class_name TouchControls
extends Control

signal editor_closed

## Referências aos nós principais
var player: CharacterBody3D = null
var hud: CanvasLayer = null

## Estado de exibição e controle
var is_active: bool = false
var force_mobile_test: bool = false
var is_editing_layout: bool = false

## Joystick Virtual (Lado Esquerdo)
var joystick_touch_index: int = -1
var joystick_center: Vector2 = Vector2(170, 550)
var joystick_knob_pos: Vector2 = Vector2(170, 550)
var base_joystick_radius: float = 65.0
var joystick_radius: float = 65.0
var joystick_scale: float = 1.0
var joystick_deadzone: float = 0.15
var joystick_output: Vector2 = Vector2.ZERO
var is_joystick_active: bool = false

## Zona de Rotação de Câmera / Mira (Lado Direito)
var look_touch_index: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

## Lista de Botões Touch
var touch_buttons: Array[Dictionary] = []

## Editor de Layout
var selected_element_id: String = "shoot" # "joystick" ou id de botão
var is_dragging_element: bool = false
var drag_touch_index: int = -1
var editor_panel: PanelContainer = null
var editor_selected_label: Label = null
var editor_size_label: Label = null

const SAVE_PATH: String = "user://touch_layout.json"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	_init_default_buttons()
	_create_editor_toolbar()
	
	# Detecta se está em dispositivo mobile com touchscreen nativo
	var is_mobile_device: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	set_active(is_mobile_device or force_mobile_test)
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_layout()

func _on_viewport_size_changed() -> void:
	_apply_layout()

func set_active(active: bool) -> void:
	is_active = active
	visible = is_active or is_editing_layout
	set_process_input(is_active or is_editing_layout)
	queue_redraw()

func _ensure_references() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not hud:
		hud = get_parent() as CanvasLayer
		if not hud and get_tree().current_scene:
			hud = get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer

## Inicializa a estrutura base dos botões
func _init_default_buttons() -> void:
	touch_buttons = [
		{
			"id": "shoot",
			"label": "TIRO",
			"icon": "🎯",
			"base_radius": 46.0,
			"radius": 46.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.91, 0.81),
			"pos": Vector2.ZERO,
			"color": Color(1.0, 0.28, 0.24, 0.65),
			"active_color": Color(1.0, 0.45, 0.4, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "aim",
			"label": "MIRA",
			"icon": "🔍",
			"base_radius": 34.0,
			"radius": 34.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.83, 0.84),
			"pos": Vector2.ZERO,
			"color": Color(0.2, 0.8, 1.0, 0.6),
			"active_color": Color(0.3, 0.95, 1.0, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "jump",
			"label": "PULO",
			"icon": "🦘",
			"base_radius": 34.0,
			"radius": 34.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.95, 0.66),
			"pos": Vector2.ZERO,
			"color": Color(0.3, 0.9, 0.4, 0.6),
			"active_color": Color(0.4, 1.0, 0.5, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "reload",
			"label": "RECARGA",
			"icon": "🔄",
			"base_radius": 30.0,
			"radius": 30.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.88, 0.69),
			"pos": Vector2.ZERO,
			"color": Color(1.0, 0.85, 0.25, 0.6),
			"active_color": Color(1.0, 0.95, 0.4, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "grenade",
			"label": "GRANADA",
			"icon": "💣",
			"base_radius": 30.0,
			"radius": 30.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.82, 0.72),
			"pos": Vector2.ZERO,
			"color": Color(1.0, 0.5, 0.2, 0.6),
			"active_color": Color(1.0, 0.7, 0.35, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "weapon",
			"label": "ARMA",
			"icon": "🔫",
			"base_radius": 30.0,
			"radius": 30.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.91, 0.56),
			"pos": Vector2.ZERO,
			"color": Color(0.85, 0.45, 1.0, 0.6),
			"active_color": Color(0.95, 0.65, 1.0, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "shop",
			"label": "LOJA",
			"icon": "🛒",
			"base_radius": 28.0,
			"radius": 28.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.06, 0.17),
			"pos": Vector2.ZERO,
			"color": Color(0.2, 0.95, 0.5, 0.65),
			"active_color": Color(0.4, 1.0, 0.7, 0.95),
			"pressed": false,
			"touch_index": -1
		},
		{
			"id": "scoreboard",
			"label": "TAB",
			"icon": "📊",
			"base_radius": 28.0,
			"radius": 28.0,
			"scale": 1.0,
			"default_ratio": Vector2(0.12, 0.17),
			"pos": Vector2.ZERO,
			"color": Color(0.35, 0.65, 1.0, 0.65),
			"active_color": Color(0.55, 0.8, 1.0, 0.95),
			"pressed": false,
			"touch_index": -1
		}
	]

## Aplica posições (salvas ou padrões)
func _apply_layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
		
	# Tenta carregar do arquivo customizado
	if not load_custom_layout():
		# Posição padrão do Joystick
		joystick_scale = 1.0
		joystick_radius = base_joystick_radius
		joystick_center = Vector2(clamp(vp_size.x * 0.14, 120.0, 200.0), vp_size.y - clamp(vp_size.y * 0.24, 120.0, 190.0))
		joystick_knob_pos = joystick_center
		
		# Posições padrão dos botões
		for btn in touch_buttons:
			btn["scale"] = 1.0
			btn["radius"] = btn["base_radius"]
			btn["pos"] = Vector2(btn["default_ratio"].x * vp_size.x, btn["default_ratio"].y * vp_size.y)
			
	if not is_joystick_active:
		joystick_knob_pos = joystick_center
	queue_redraw()

## =============================================================================
## PERSISTÊNCIA (SALVAR / CARREGAR / RESETAR)
## =============================================================================

func save_custom_layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
		
	var data := {
		"joystick": {
			"ratio_x": joystick_center.x / vp_size.x,
			"ratio_y": joystick_center.y / vp_size.y,
			"scale": joystick_scale
		},
		"buttons": {}
	}
	
	for btn in touch_buttons:
		data["buttons"][btn["id"]] = {
			"ratio_x": btn["pos"].x / vp_size.x,
			"ratio_y": btn["pos"].y / vp_size.y,
			"scale": btn["scale"]
		}
		
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		print("[TOUCH] Layout de botões salvo com sucesso em: %s" % SAVE_PATH)

func load_custom_layout() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
		
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
		
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return false
		
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return false
		
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
		
	if data.has("joystick"):
		var j_data = data["joystick"]
		joystick_scale = j_data.get("scale", 1.0)
		joystick_radius = base_joystick_radius * joystick_scale
		joystick_center = Vector2(j_data.get("ratio_x", 0.14) * vp_size.x, j_data.get("ratio_y", 0.76) * vp_size.y)
		joystick_knob_pos = joystick_center
		
	if data.has("buttons"):
		var b_dict = data["buttons"]
		for btn in touch_buttons:
			var b_id = btn["id"]
			if b_dict.has(b_id):
				var b_data = b_dict[b_id]
				btn["scale"] = b_data.get("scale", 1.0)
				btn["radius"] = btn["base_radius"] * btn["scale"]
				btn["pos"] = Vector2(b_data.get("ratio_x", 0.5) * vp_size.x, b_data.get("ratio_y", 0.5) * vp_size.y)
				
	return true

func reset_to_defaults() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
		
	joystick_scale = 1.0
	joystick_radius = base_joystick_radius
	joystick_center = Vector2(clamp(vp_size.x * 0.14, 120.0, 200.0), vp_size.y - clamp(vp_size.y * 0.24, 120.0, 190.0))
	joystick_knob_pos = joystick_center
	
	for btn in touch_buttons:
		btn["scale"] = 1.0
		btn["radius"] = btn["base_radius"]
		btn["pos"] = Vector2(btn["default_ratio"].x * vp_size.x, btn["default_ratio"].y * vp_size.y)
		
	_update_editor_labels()
	queue_redraw()
	AudioManager.play("empty_click", 0.0, 1.0)

## =============================================================================
## BARRA DE FERRAMENTAS DO EDITOR DE LAYOUT
## =============================================================================

func _create_editor_toolbar() -> void:
	editor_panel = PanelContainer.new()
	editor_panel.name = "EditorToolbar"
	editor_panel.visible = false
	editor_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Estilo visual translúcido escuro
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.85, 1.0, 0.8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	editor_panel.add_theme_stylebox_override("panel", style)
	
	# Posicionamento centralizado no topo
	editor_panel.layout_mode = 1
	editor_panel.anchors_preset = Control.PRESET_TOP_WIDE
	editor_panel.offset_left = 60
	editor_panel.offset_right = -60
	editor_panel.offset_top = 12
	editor_panel.offset_bottom = 74
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	editor_panel.add_child(hbox)
	
	# Rótulo de Instrução e Seleção
	editor_selected_label = Label.new()
	editor_selected_label.text = "🎯 Arraste os botões | Selecionado: TIRO"
	editor_selected_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	editor_selected_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(editor_selected_label)
	
	# Botão Diminuir Tamanho (-)
	var btn_minus := Button.new()
	btn_minus.text = "➖ Menor"
	btn_minus.custom_minimum_size = Vector2(85, 38)
	btn_minus.focus_mode = Control.FOCUS_NONE
	btn_minus.pressed.connect(_on_scale_down_pressed)
	hbox.add_child(btn_minus)
	
	# Rótulo de Tamanho
	editor_size_label = Label.new()
	editor_size_label.text = "100%"
	editor_size_label.custom_minimum_size = Vector2(50, 0)
	editor_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	editor_size_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	editor_size_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(editor_size_label)
	
	# Botão Aumentar Tamanho (+)
	var btn_plus := Button.new()
	btn_plus.text = "➕ Maior"
	btn_plus.custom_minimum_size = Vector2(85, 38)
	btn_plus.focus_mode = Control.FOCUS_NONE
	btn_plus.pressed.connect(_on_scale_up_pressed)
	hbox.add_child(btn_plus)
	
	# Botão Restaurar Padrão
	var btn_reset := Button.new()
	btn_reset.text = "🔄 Padrão"
	btn_reset.custom_minimum_size = Vector2(90, 38)
	btn_reset.focus_mode = Control.FOCUS_NONE
	btn_reset.pressed.connect(reset_to_defaults)
	hbox.add_child(btn_reset)
	
	# Botão Salvar e Sair
	var btn_save := Button.new()
	btn_save.text = "💾 Salvar e Voltar"
	btn_save.custom_minimum_size = Vector2(130, 38)
	btn_save.focus_mode = Control.FOCUS_NONE
	btn_save.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	btn_save.pressed.connect(close_layout_editor)
	hbox.add_child(btn_save)
	
	add_child(editor_panel)

func start_layout_editor() -> void:
	is_editing_layout = true
	visible = true
	set_process_input(true)
	if editor_panel:
		editor_panel.visible = true
	selected_element_id = "shoot"
	_update_editor_labels()
	queue_redraw()
	AudioManager.play("buy", 0.0, 1.2)

func close_layout_editor() -> void:
	save_custom_layout()
	is_editing_layout = false
	if editor_panel:
		editor_panel.visible = false
	
	# Restaura visibilidade normal conforme detecção mobile
	var is_mobile_device: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	set_active(is_mobile_device or force_mobile_test)
	
	queue_redraw()
	editor_closed.emit()
	AudioManager.play("buy", 0.0, 1.0)

func _on_scale_down_pressed() -> void:
	_adjust_selected_scale(-0.1)

func _on_scale_up_pressed() -> void:
	_adjust_selected_scale(0.1)

func _adjust_selected_scale(delta_val: float) -> void:
	if selected_element_id == "joystick":
		joystick_scale = clamp(joystick_scale + delta_val, 0.6, 2.2)
		joystick_radius = base_joystick_radius * joystick_scale
	else:
		for btn in touch_buttons:
			if btn["id"] == selected_element_id:
				btn["scale"] = clamp(btn["scale"] + delta_val, 0.6, 2.2)
				btn["radius"] = btn["base_radius"] * btn["scale"]
				break
				
	_update_editor_labels()
	queue_redraw()
	AudioManager.play("empty_click", 0.0, 1.4)

func _update_editor_labels() -> void:
	if not editor_selected_label or not editor_size_label:
		return
		
	if selected_element_id == "joystick":
		editor_selected_label.text = "🎯 Arraste | Selecionado: JOYSTICK ANALÓGICO"
		editor_size_label.text = "%d%%" % int(round(joystick_scale * 100))
	else:
		for btn in touch_buttons:
			if btn["id"] == selected_element_id:
				editor_selected_label.text = "🎯 Arraste | Selecionado: %s %s" % [btn["icon"], btn["label"]]
				editor_size_label.text = "%d%%" % int(round(btn["scale"] * 100))
				break

## =============================================================================
## PROCESSAMENTO DE INPUT (TOUCH / MOUSE)
## =============================================================================

func _input(event: InputEvent) -> void:
	if not is_active and not is_editing_layout:
		return
	_ensure_references()
	
	# MODO DE EDIÇÃO DE LAYOUT: Arrastar e soltar botões
	if is_editing_layout:
		_handle_editor_input(event)
		return
		
	# MODO NORMAL DE JOGO:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position, event.relative)
	elif force_mobile_test:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(999, event.position, event.pressed)
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_drag(999, event.position, event.relative)

func _handle_editor_input(event: InputEvent) -> void:
	# Ignora toques que colidem com a barra de ferramentas superior
	if editor_panel and editor_panel.visible:
		var panel_rect = editor_panel.get_global_rect()
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if panel_rect.has_point(event.position):
				return
				
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var touch_idx: int = event.index if event is InputEventScreenTouch else 999
		var pos: Vector2 = event.position
		var is_down: bool = event.pressed
		
		if is_down:
			# 1. Verifica se tocou no Joystick
			if pos.distance_to(joystick_center) <= joystick_radius * 1.3:
				selected_element_id = "joystick"
				is_dragging_element = true
				drag_touch_index = touch_idx
				_update_editor_labels()
				queue_redraw()
				return
				
			# 2. Verifica se tocou em algum botão de ação
			for btn in touch_buttons:
				if pos.distance_to(btn["pos"]) <= btn["radius"] * 1.3:
					selected_element_id = btn["id"]
					is_dragging_element = true
					drag_touch_index = touch_idx
					_update_editor_labels()
					queue_redraw()
					return
		else:
			if touch_idx == drag_touch_index:
				is_dragging_element = false
				drag_touch_index = -1
				queue_redraw()
				
	elif (event is InputEventScreenDrag or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))) and is_dragging_element:
		var vp_size = get_viewport_rect().size
		var target_pos = Vector2(
			clamp(event.position.x, 40.0, vp_size.x - 40.0),
			clamp(event.position.y, 85.0, vp_size.y - 40.0)
		)
		
		if selected_element_id == "joystick":
			joystick_center = target_pos
			joystick_knob_pos = target_pos
		else:
			for btn in touch_buttons:
				if btn["id"] == selected_element_id:
					btn["pos"] = target_pos
					break
		queue_redraw()

func _handle_touch(touch_idx: int, pos: Vector2, is_down: bool) -> void:
	var vp_width: float = get_viewport_rect().size.x
	var is_left_half: bool = (pos.x < vp_width * 0.45)
	
	if is_down:
		for btn in touch_buttons:
			var dist = pos.distance_to(btn["pos"])
			if dist <= (btn["radius"] * 1.25):
				btn["pressed"] = true
				btn["touch_index"] = touch_idx
				_execute_button_action(btn["id"], true)
				queue_redraw()
				return
				
		if is_left_half and joystick_touch_index == -1:
			joystick_touch_index = touch_idx
			is_joystick_active = true
			joystick_center = pos
			joystick_knob_pos = pos
			queue_redraw()
			return
			
		elif not is_left_half and look_touch_index == -1:
			look_touch_index = touch_idx
			last_look_pos = pos
			return
			
	else:
		for btn in touch_buttons:
			if btn["touch_index"] == touch_idx:
				btn["pressed"] = false
				btn["touch_index"] = -1
				_execute_button_action(btn["id"], false)
				queue_redraw()
				
		if touch_idx == joystick_touch_index:
			joystick_touch_index = -1
			is_joystick_active = false
			joystick_output = Vector2.ZERO
			joystick_knob_pos = joystick_center
			if player:
				player.touch_move_vector = Vector2.ZERO
			queue_redraw()
			
		if touch_idx == look_touch_index:
			look_touch_index = -1

func _handle_drag(touch_idx: int, pos: Vector2, relative_motion: Vector2) -> void:
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
			joystick_output = Vector2(norm_vec.x, norm_vec.y)
			
		if player:
			player.touch_move_vector = joystick_output
		queue_redraw()
		
	elif touch_idx == look_touch_index:
		var delta_look: Vector2 = pos - last_look_pos
		last_look_pos = pos
		if player and player.has_method("apply_touch_look"):
			player.apply_touch_look(delta_look)

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

## =============================================================================
## RENDERIZAÇÃO 2D (CANVAS DRAW)
## =============================================================================

func _draw() -> void:
	if not is_active and not is_editing_layout:
		return
		
	# Em modo de edição, escurece levemente o fundo para destacar os botões
	if is_editing_layout:
		draw_rect(get_viewport_rect(), Color(0, 0, 0, 0.45))
		
	var default_font := ThemeDB.fallback_font
	
	# 1. Desenho do Joystick Virtual
	var base_col = Color(1.0, 1.0, 1.0, 0.15) if not is_joystick_active else Color(0.2, 0.9, 1.0, 0.25)
	var ring_col = Color(1.0, 1.0, 1.0, 0.4) if not is_joystick_active else Color(0.3, 1.0, 1.0, 0.75)
	
	if is_editing_layout and selected_element_id == "joystick":
		# Destaque de seleção no Joystick
		draw_circle(joystick_center, joystick_radius + 10.0, Color(1.0, 0.88, 0.2, 0.2))
		draw_arc(joystick_center, joystick_radius + 10.0, 0, TAU, 36, Color(1.0, 0.88, 0.2, 0.95), 3.0)
		draw_string(default_font, joystick_center + Vector2(-36, -joystick_radius - 16), "JOYSTICK", HORIZONTAL_ALIGNMENT_CENTER, 72, 12, Color(1.0, 0.9, 0.3))
		
	draw_circle(joystick_center, joystick_radius, base_col)
	draw_arc(joystick_center, joystick_radius, 0, TAU, 32, ring_col, 2.5)
	draw_arc(joystick_center + Vector2(0, -joystick_radius * 0.9), 12.0 * joystick_scale, 0, TAU, 16, Color(1, 1, 1, 0.3), 1.5)
	
	var knob_col = Color(0.25, 0.85, 1.0, 0.6) if is_joystick_active else Color(0.9, 0.9, 0.9, 0.4)
	draw_circle(joystick_knob_pos, 28.0 * joystick_scale, knob_col)
	draw_circle(joystick_knob_pos, 8.0 * joystick_scale, Color(1.0, 1.0, 1.0, 0.85))
	
	# 2. Desenho de Todos os Botões de Ação
	for btn in touch_buttons:
		var b_pos: Vector2 = btn["pos"]
		var b_rad: float = btn["radius"]
		var is_btn_down: bool = btn["pressed"]
		var is_selected: bool = (is_editing_layout and selected_element_id == btn["id"])
		
		# Anel de Destaque no elemento selecionado no editor
		if is_selected:
			draw_circle(b_pos, b_rad + 8.0, Color(1.0, 0.88, 0.2, 0.22))
			draw_arc(b_pos, b_rad + 8.0, 0, TAU, 36, Color(1.0, 0.88, 0.2, 0.95), 3.0)
			
		var fill_color: Color = btn["active_color"] if (is_btn_down or is_selected) else btn["color"]
		var border_color: Color = Color(1.0, 1.0, 1.0, 0.85) if (is_btn_down or is_selected) else Color(1.0, 1.0, 1.0, 0.45)
		var scale_rad: float = b_rad * (1.12 if is_btn_down else 1.0)
		
		draw_circle(b_pos, scale_rad, fill_color)
		draw_arc(b_pos, scale_rad, 0, TAU, 28, border_color, 2.2)
		
		# Ícone e texto escalonados com o botão
		var font_size: int = int(round(12.0 * btn["scale"]))
		var icon_font_size: int = int(round(18.0 * btn["scale"]))
		
		var icon_str: String = btn["icon"]
		draw_string(default_font, b_pos + Vector2(-icon_font_size * 0.55, -2 * btn["scale"]), icon_str, HORIZONTAL_ALIGNMENT_CENTER, -1, icon_font_size)
		
		var label_str: String = btn["label"]
		draw_string(default_font, b_pos + Vector2(-28 * btn["scale"], 18 * btn["scale"]), label_str, HORIZONTAL_ALIGNMENT_CENTER, int(56 * btn["scale"]), font_size, Color(1, 1, 1, 0.95))
