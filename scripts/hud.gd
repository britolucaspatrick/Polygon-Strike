extends CanvasLayer

signal start_match_requested(time_limit_sec: float, target_kills: int, difficulty: String)
signal host_match_requested(port: int, use_upnp: bool, time_limit_sec: float, target_kills: int, difficulty: String)
signal join_match_requested(ip: String, port: int, player_name: String, player_team: String)

## Referências aos nós de interface
@onready var blue_score_label: Label = $HUDControl/TopScoreBar/VBoxContainer/HBoxContainer/BlueScore
@onready var red_score_label: Label = $HUDControl/TopScoreBar/VBoxContainer/HBoxContainer/RedScore
@onready var hp_label: Label = $HUDControl/BottomLeft/VBoxContainer/HPLabel
@onready var hp_bar: ProgressBar = $HUDControl/BottomLeft/VBoxContainer/HPBar
@onready var killfeed_container: VBoxContainer = $HUDControl/TopRightKillfeed/KillfeedVBox
@onready var damage_flash: ColorRect = $HUDControl/DamageFlash
@onready var game_over_panel: PanelContainer = $HUDControl/GameOverPanel
@onready var game_over_title: Label = $HUDControl/GameOverPanel/VBoxContainer/TitleLabel
@onready var game_over_detail: Label = $HUDControl/GameOverPanel/VBoxContainer/DetailLabel

# Nós do TopBar
@onready var match_timer_label: Label = %MatchTimerLabel
@onready var goal_label: Label = %GoalLabel

# Nós da Configuração de Partida
@onready var match_setup_panel: PanelContainer = %MatchSetupPanel
@onready var setup_summary_label: Label = %SetupSummaryLabel
@onready var event_notification_label: Label = %EventNotificationLabel

# Nós do Scoreboard (Tabela TAB)
@onready var scoreboard_panel: PanelContainer = %ScoreboardPanel
@onready var scoreboard_header_label: Label = %SubHeaderLabel
@onready var blue_rows_container: VBoxContainer = %BlueRowsContainer
@onready var red_rows_container: VBoxContainer = %RedRowsContainer

# Nós de Recursos e Mercado (CTRL)
@onready var ammo_label: Label = %AmmoLabel
@onready var weapon_name_label: Label = %WeaponNameLabel
@onready var money_label: Label = %MoneyLabel
@onready var grenade_label: Label = %GrenadeLabel
@onready var buy_zone_hint: Label = %BuyZoneHint
@onready var buy_menu_panel: PanelContainer = %BuyMenuPanel
@onready var shop_money_label: Label = %ShopMoneyLabel
@onready var shop_status_label: Label = %ShopStatusLabel
@onready var shop_msg_label: Label = %ShopMsgLabel
@onready var crosshair: Control = $HUDControl/Crosshair

var flash_tween: Tween
var notification_tween: Tween
var player_ref: Node = null

var selected_time_seconds: float = 300.0
var selected_target_kills: int = 25
var selected_difficulty: String = "normal"
var current_game_mode: String = "single" # "single", "host", "join"
var join_team: String = "red" # "blue" ou "red"
var is_in_match_setup: bool = true
var is_game_over: bool = false

func _ready() -> void:
	_ensure_references()
	update_scores(0, 0)
	update_player_hp(100, 100)
	if game_over_panel:
		game_over_panel.visible = false
	if scoreboard_panel:
		scoreboard_panel.visible = false
	if buy_menu_panel:
		buy_menu_panel.visible = false
		
	# Conecta os botões de compra do mercado e de setup de partida
	_setup_shop_buttons()
	_setup_config_panel_buttons()
	
	if match_setup_panel:
		match_setup_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	# Detecta IP local para já exibir na interface do Host
	var local_ip = _detect_local_ip()
	var host_ip_label = find_child("HostIpLabel", true, false) as Label
	if host_ip_label:
		host_ip_label.text = "🏠 IP Local da sua rede (Wi-Fi): %s:7777" % local_ip

func _detect_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or (addr.begins_with("172.") and not addr.contains(":")):
			return addr
	return "127.0.0.1"

func _input(event: InputEvent) -> void:
	if is_in_match_setup:
		return
		
	# Se a partida acabou, o placar detalhado permanece sempre aberto na tela
	if is_game_over:
		return
		
	# Segurar TAB para ver Scoreboard
	if event.is_action("scoreboard"):
		if event.is_pressed():
			set_scoreboard_visible(true)
		else:
			set_scoreboard_visible(false)
			
	# Segurar CTRL para abrir o Mercado da Base
	if event.is_action("buy_menu"):
		if event.is_pressed():
			set_buy_menu_visible(true)
		else:
			set_buy_menu_visible(false)
			set_buy_menu_visible(false)

## Abre ou fecha o menu de compras
func set_buy_menu_visible(visible_state: bool) -> void:
	_ensure_references()
	if buy_menu_panel:
		buy_menu_panel.visible = visible_state
		if visible_state:
			# Libera o cursor do mouse para clicar nos itens
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if player_ref:
				_update_shop_display()
		else:
			# Recaptura o mouse ao fechar (se o placar também não estiver aberto)
			if scoreboard_panel and scoreboard_panel.visible:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _update_shop_display() -> void:
	if not player_ref:
		_find_player_ref()
	if not player_ref:
		return
	if shop_money_label:
		shop_money_label.text = "SEU SALDO: $%d" % player_ref.money
	if shop_status_label:
		if player_ref.is_in_buy_zone:
			shop_status_label.text = "🟢 VOCÊ ESTÁ NA BASE AZUL (COMPRAS, RECARGAS E CURA 100%)"
			shop_status_label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.4))
		else:
			shop_status_label.text = "🔴 VOCÊ ESTÁ FORA DA BASE! Volte à Base Azul para comprar."
			shop_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			
	# Bloqueio de recompra de munição se estiver 100% carregado
	var btn_ammo = find_child("BtnBuyAmmo", true, false) as Button
	if btn_ammo and player_ref.has_method("is_ammo_full"):
		var is_full: bool = player_ref.is_ammo_full()
		btn_ammo.disabled = is_full
		if is_full:
			btn_ammo.text = "Munição 100% Cheia [BLOQUEADO]\n(Capacidade Máxima Atingida)"
		else:
			btn_ammo.text = "Reabastecer Munição ($200)\nEnche Todas as Armas"
			
	# Bloqueio de granada se já atingiu o limite
	var btn_grenade = find_child("BtnBuyGrenade", true, false) as Button
	if btn_grenade and "grenades_count" in player_ref and "max_grenades" in player_ref:
		var nades_full: bool = (player_ref.grenades_count >= player_ref.max_grenades)
		btn_grenade.disabled = nades_full
		if nades_full:
			btn_grenade.text = "Granadas no Máximo (%d/%d) [CHEIO]\n(Capacidade Máxima)" % [player_ref.grenades_count, player_ref.max_grenades]
		else:
			btn_grenade.text = "Granada Fragmentária ($300)\nDano em Área (Tecla F)"

## Configura botões de compra do mercado
func _setup_shop_buttons() -> void:
	var buttons_to_setup: Array = [
		{"name": "BtnBuyMagnum", "id": "magnum"},
		{"name": "BtnBuySMG", "id": "smg"},
		{"name": "BtnBuyRifle", "id": "rifle"},
		{"name": "BtnBuyLMG", "id": "lmg"},
		{"name": "BtnBuyGrenade", "id": "grenade"},
		{"name": "BtnBuyAmmo", "id": "ammo"}
	]
	for item in buttons_to_setup:
		var btn = find_child(item["name"], true, false) as Button
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			if not btn.pressed.is_connected(_on_buy_button_pressed.bind(item["id"])):
				btn.pressed.connect(_on_buy_button_pressed.bind(item["id"]))

func _on_buy_button_pressed(item_id: String) -> void:
	if not player_ref:
		_find_player_ref()
	if player_ref and player_ref.has_method("buy_item"):
		var result: Dictionary = player_ref.buy_item(item_id)
		if shop_msg_label:
			shop_msg_label.text = result.get("message", "")
			if result.get("success", false):
				shop_msg_label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.4))
			else:
				shop_msg_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		_update_shop_display()

func _find_player_ref() -> void:
	player_ref = get_tree().get_first_node_in_group("player")

## Atualiza informações de munição no HUD
func update_player_ammo(current_clip: int, reserve_ammo: int, weapon_name: String) -> void:
	_ensure_references()
	if weapon_name_label:
		weapon_name_label.text = "🔫 %s" % weapon_name
	if ammo_label:
		ammo_label.text = "MUNIÇÃO: %d / %d" % [current_clip, reserve_ammo]
		if current_clip == 0 and reserve_ammo == 0:
			ammo_label.text = "SEM MUNIÇÃO! (VOLTE À BASE)"
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
		elif current_clip == 0:
			ammo_label.text = "RECARREGUE! [R] (%d)" % reserve_ammo
			ammo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

## Atualiza dinheiro no HUD
func update_player_money(amount: int) -> void:
	_ensure_references()
	if money_label:
		money_label.text = "💰 $%d" % amount
	if shop_money_label:
		shop_money_label.text = "SEU SALDO: $%d" % amount

## Atualiza granadas no HUD
func update_player_grenades(count: int) -> void:
	_ensure_references()
	if grenade_label:
		grenade_label.text = "💣 GRANADAS [F]: %d / 3" % count

## Atualiza indicação de zona de compra
func update_buy_zone_status(in_buy_zone: bool) -> void:
	_ensure_references()
	if buy_zone_hint:
		buy_zone_hint.visible = in_buy_zone
		if in_buy_zone:
			buy_zone_hint.text = "🟢 BASE AZUL: Vida 100% | Segure [CTRL] para o Mercado"

## Atualiza a retícula na tela quando o jogador usa a mira com botão direito (ADS)
func update_aim_status(is_aiming: bool) -> void:
	if not crosshair:
		crosshair = find_child("Crosshair", true, false) as Control
	if not crosshair:
		return
		
	var dot = crosshair.get_node_or_null("Dot") as ColorRect
	var top = crosshair.get_node_or_null("Top") as ColorRect
	var bottom = crosshair.get_node_or_null("Bottom") as ColorRect
	var left = crosshair.get_node_or_null("Left") as ColorRect
	var right = crosshair.get_node_or_null("Right") as ColorRect
	
	if is_aiming:
		if dot:
			dot.color = Color(0.2, 0.95, 1.0, 1.0)
		if top:
			top.offset_top = -9.0
			top.offset_bottom = -3.0
			top.color = Color(0.2, 0.95, 1.0, 0.7)
		if bottom:
			bottom.offset_top = 3.0
			bottom.offset_bottom = 9.0
			bottom.color = Color(0.2, 0.95, 1.0, 0.7)
		if left:
			left.offset_left = -9.0
			left.offset_right = -3.0
			left.color = Color(0.2, 0.95, 1.0, 0.7)
		if right:
			right.offset_left = 3.0
			right.offset_right = 9.0
			right.color = Color(0.2, 0.95, 1.0, 0.7)
	else:
		if dot:
			dot.color = Color(1.0, 1.0, 1.0, 0.95)
		if top:
			top.offset_top = -14.0
			top.offset_bottom = -6.0
			top.color = Color(1.0, 1.0, 1.0, 0.85)
		if bottom:
			bottom.offset_top = 6.0
			bottom.offset_bottom = 14.0
			bottom.color = Color(1.0, 1.0, 1.0, 0.85)
		if left:
			left.offset_left = -14.0
			left.offset_right = -6.0
			left.color = Color(1.0, 1.0, 1.0, 0.85)
		if right:
			right.offset_left = 6.0
			right.offset_right = 14.0
			right.color = Color(1.0, 1.0, 1.0, 0.85)

## Exibe ou oculta a tabela do Scoreboard
func set_scoreboard_visible(visible_state: bool) -> void:
	_ensure_references()
	if scoreboard_panel:
		scoreboard_panel.visible = visible_state
		if visible_state:
			var main_node = get_parent()
			if main_node and main_node.has_method("get_scoreboard_data"):
				refresh_scoreboard(main_node.get_scoreboard_data())

## Garante referências mesmo com mudanças de cena
func _ensure_references() -> void:
	if not player_ref:
		_find_player_ref()
	if not blue_score_label:
		blue_score_label = find_child("BlueScore", true, false) as Label
	if not red_score_label:
		red_score_label = find_child("RedScore", true, false) as Label
	if not hp_label:
		hp_label = find_child("HPLabel", true, false) as Label
	if not hp_bar:
		hp_bar = find_child("HPBar", true, false) as ProgressBar
	if not killfeed_container:
		killfeed_container = find_child("KillfeedVBox", true, false) as VBoxContainer
	if not damage_flash:
		damage_flash = find_child("DamageFlash", true, false) as ColorRect
	if not game_over_panel:
		game_over_panel = find_child("GameOverPanel", true, false) as PanelContainer
	if not game_over_title:
		game_over_title = find_child("TitleLabel", true, false) as Label
	if not game_over_detail:
		game_over_detail = find_child("DetailLabel", true, false) as Label
	if not scoreboard_panel:
		scoreboard_panel = find_child("ScoreboardPanel", true, false) as PanelContainer
	if not scoreboard_header_label:
		scoreboard_header_label = find_child("SubHeaderLabel", true, false) as Label
	if not blue_rows_container:
		blue_rows_container = find_child("BlueRowsContainer", true, false) as VBoxContainer
	if not red_rows_container:
		red_rows_container = find_child("RedRowsContainer", true, false) as VBoxContainer
	if not ammo_label:
		ammo_label = find_child("AmmoLabel", true, false) as Label
	if not weapon_name_label:
		weapon_name_label = find_child("WeaponNameLabel", true, false) as Label
	if not money_label:
		money_label = find_child("MoneyLabel", true, false) as Label
	if not grenade_label:
		grenade_label = find_child("GrenadeLabel", true, false) as Label
	if not buy_zone_hint:
		buy_zone_hint = find_child("BuyZoneHint", true, false) as Label
	if not buy_menu_panel:
		buy_menu_panel = find_child("BuyMenuPanel", true, false) as PanelContainer
	if not shop_money_label:
		shop_money_label = find_child("ShopMoneyLabel", true, false) as Label
	if not shop_status_label:
		shop_status_label = find_child("ShopStatusLabel", true, false) as Label
	if not shop_msg_label:
		shop_msg_label = find_child("ShopMsgLabel", true, false) as Label

func update_scores(blue: int, red: int) -> void:
	_ensure_references()
	if blue_score_label:
		if blue_score_label.text != str(blue):
			blue_score_label.text = str(blue)
			_pulse_label(blue_score_label)
		else:
			blue_score_label.text = str(blue)
			
	if red_score_label:
		if red_score_label.text != str(red):
			red_score_label.text = str(red)
			_pulse_label(red_score_label)
		else:
			red_score_label.text = str(red)

func _pulse_label(label: Label) -> void:
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12)

## Atualiza em tempo real o ranking na tabela do TAB
func refresh_scoreboard(data: Dictionary) -> void:
	_ensure_references()
	if not scoreboard_panel or not scoreboard_panel.visible:
		return
		
	if scoreboard_header_label:
		scoreboard_header_label.text = "AZUL [ %d ]   VS   [ %d ] VERMELHO   •   PRIMEIRO A %d ABATES" % [
			data.get("blue_score", 0),
			data.get("red_score", 0),
			data.get("target_score", 25)
		]
		
	if blue_rows_container and "blue_team" in data:
		_populate_team_table(blue_rows_container, data["blue_team"], true)
		
	if red_rows_container and "red_team" in data:
		_populate_team_table(red_rows_container, data["red_team"], false)

## Preenche a lista de um time na tabela ordenada por pontos
func _populate_team_table(container: VBoxContainer, team_members: Array, is_blue: bool) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
		
	var rank: int = 1
	for member in team_members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 24)
		
		var is_local_player: bool = member.get("is_player", false)
		
		# Posição (#1, #2...)
		var rank_lbl := Label.new()
		rank_lbl.text = "#%d" % rank
		rank_lbl.custom_minimum_size = Vector2(28, 0)
		rank_lbl.add_theme_font_size_override("font_size", 14)
		rank_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(rank_lbl)
		
		# Nome
		var name_lbl := Label.new()
		var display_name: String = member.get("name", "Combatente")
		if is_local_player:
			name_lbl.text = "★ Você"
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
		else:
			name_lbl.text = display_name
			if is_blue:
				name_lbl.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))
			else:
				name_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
				
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(name_lbl)
		
		# Abates (K)
		var k_lbl := Label.new()
		k_lbl.text = str(member.get("kills", 0))
		k_lbl.custom_minimum_size = Vector2(40, 0)
		k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		k_lbl.add_theme_font_size_override("font_size", 14)
		k_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.4))
		row.add_child(k_lbl)
		
		# Mortes (D)
		var d_lbl := Label.new()
		d_lbl.text = str(member.get("deaths", 0))
		d_lbl.custom_minimum_size = Vector2(40, 0)
		d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_lbl.add_theme_font_size_override("font_size", 14)
		d_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
		row.add_child(d_lbl)
		
		# Dano
		var dmg_lbl := Label.new()
		dmg_lbl.text = str(member.get("damage", 0))
		dmg_lbl.custom_minimum_size = Vector2(50, 0)
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dmg_lbl.add_theme_font_size_override("font_size", 14)
		dmg_lbl.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
		row.add_child(dmg_lbl)
		
		# Pontos
		var score_lbl := Label.new()
		score_lbl.text = str(member.get("score", 0))
		score_lbl.custom_minimum_size = Vector2(55, 0)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_lbl.add_theme_font_size_override("font_size", 14)
		score_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		row.add_child(score_lbl)
		
		container.add_child(row)
		rank += 1

func update_player_hp(current_hp: int, max_hp: int) -> void:
	_ensure_references()
	if hp_label:
		hp_label.text = "VIDA: %d / %d" % [current_hp, max_hp]
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
		
		var hp_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		if hp_ratio > 0.5:
			hp_bar.modulate = Color(0.2, 0.9, 0.3)
		elif hp_ratio > 0.25:
			hp_bar.modulate = Color(0.95, 0.8, 0.2)
		else:
			hp_bar.modulate = Color(0.95, 0.2, 0.2)

func trigger_damage_flash() -> void:
	_ensure_references()
	if not damage_flash:
		return
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
		
	damage_flash.color = Color(0.8, 0.1, 0.1, 0.35)
	flash_tween = create_tween()
	flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.25)

func trigger_heal_flash() -> void:
	_ensure_references()
	if not damage_flash:
		return
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
		
	damage_flash.color = Color(0.1, 0.8, 0.3, 0.25)
	flash_tween = create_tween()
	flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.35)

func add_killfeed_entry(killer_name: String, killer_team: String, victim_name: String, victim_team: String, is_headshot: bool = false) -> void:
	_ensure_references()
	if not killfeed_container:
		return
		
	var label := Label.new()
	var sep_str := " [🎯 HEADSHOT] ➔ " if is_headshot else " ➔ "
	label.text = "%s [%s]%s%s [%s]" % [killer_name, killer_team.to_upper(), sep_str, victim_name, victim_team.to_upper()]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	if is_headshot:
		label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	elif killer_team == "blue":
		label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	else:
		label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		
	killfeed_container.add_child(label)
	
	if killfeed_container.get_child_count() > 6:
		killfeed_container.get_child(0).queue_free()
		
	var tween := label.create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

## Exibe notificação de destaque com banner no centro da tela ao abater por headshot
func show_headshot_banner() -> void:
	show_event_notification("🎯 HEADSHOT! ELIMINAÇÃO CONFIRMADA!", Color(1.0, 0.2, 0.2))

func show_game_over(winner_team: String, final_blue: int, final_red: int, custom_detail: String = "") -> void:
	_ensure_references()
	is_game_over = true
	
	# Fecha painéis secundários
	if buy_menu_panel:
		buy_menu_panel.visible = false
	if match_setup_panel:
		match_setup_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = false
		
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Exibe o placar detalhado completo de forma permanente
	set_scoreboard_visible(true)
	
	if scoreboard_header_label:
		if winner_team == "blue":
			scoreboard_header_label.text = "🏆 FIM DE PARTIDA: VITÓRIA DO TIME AZUL! (AZUL %d  x  %d VERMELHO)" % [final_blue, final_red]
			scoreboard_header_label.add_theme_color_override("font_color", Color(0.35, 0.8, 1.0))
		elif winner_team == "red":
			scoreboard_header_label.text = "💀 FIM DE PARTIDA: VITÓRIA DO TIME VERMELHO! (AZUL %d  x  %d VERMELHO)" % [final_blue, final_red]
			scoreboard_header_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			scoreboard_header_label.text = "⚖️ FIM DE PARTIDA: EMPATE! (AZUL %d  x  %d VERMELHO)" % [final_blue, final_red]
			scoreboard_header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			
	var footer = find_child("FooterHint", true, false) as Label
	if footer:
		if custom_detail != "":
			footer.text = "%s • Pressione [F3] para Jogar Novamente / Configurar" % custom_detail
		else:
			footer.text = "Placar Final • Pressione [F3] para Jogar Novamente / Configurar"

## Atualiza o relógio da partida no HUD superior
func update_match_timer(seconds_left: float) -> void:
	_ensure_references()
	if not match_timer_label:
		match_timer_label = find_child("MatchTimerLabel", true, false) as Label
	if not match_timer_label:
		return
		
	if seconds_left < 0:
		match_timer_label.text = "⏱️ SEM LIMITE"
		match_timer_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		return
		
	var mins: int = int(seconds_left) / 60
	var secs: int = int(seconds_left) % 60
	match_timer_label.text = "⏱️ %02d:%02d" % [mins, secs]
	
	if seconds_left <= 30.0:
		match_timer_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	elif seconds_left <= 60.0:
		match_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		match_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

## Atualiza a descrição da meta da partida
func set_goal_text(text: String) -> void:
	_ensure_references()
	if not goal_label:
		goal_label = find_child("GoalLabel", true, false) as Label
	if goal_label:
		goal_label.text = text

## Exibe notificação de evento no centro da tela (ex: Invasão de Base)
func show_event_notification(msg: String, color: Color = Color(1.0, 0.85, 0.2)) -> void:
	_ensure_references()
	if not event_notification_label:
		event_notification_label = find_child("EventNotificationLabel", true, false) as Label
	if not event_notification_label:
		return
		
	if notification_tween and notification_tween.is_valid():
		notification_tween.kill()
		
	event_notification_label.text = msg
	event_notification_label.add_theme_color_override("font_color", color)
	event_notification_label.modulate.a = 1.0
	event_notification_label.visible = true
	
	notification_tween = create_tween()
	notification_tween.tween_interval(2.5)
	notification_tween.tween_property(event_notification_label, "modulate:a", 0.0, 0.7)
	notification_tween.tween_callback(func(): event_notification_label.visible = false)

## Configura botões da tela de configuração inicial de partida
func _setup_config_panel_buttons() -> void:
	# Botões de modo de jogo (Solo, Host, Join)
	var mode_buttons = {
		"BtnModeSingle": "single",
		"BtnModeHost": "host",
		"BtnModeJoin": "join"
	}
	for btn_name in mode_buttons:
		var btn = find_child(btn_name, true, false) as Button
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_mode_button_pressed.bind(mode_buttons[btn_name], btn_name))

	# Botões de seleção de time no Join
	var btn_team_blue = find_child("BtnJoinTeamBlue", true, false) as Button
	if btn_team_blue:
		btn_team_blue.focus_mode = Control.FOCUS_NONE
		btn_team_blue.pressed.connect(func(): _set_join_team("blue"))
	var btn_team_red = find_child("BtnJoinTeamRed", true, false) as Button
	if btn_team_red:
		btn_team_red.focus_mode = Control.FOCUS_NONE
		btn_team_red.pressed.connect(func(): _set_join_team("red"))

	var time_buttons = {
		"BtnTime1": 60.0,
		"BtnTime3": 180.0,
		"BtnTime5": 300.0,
		"BtnTime10": 600.0,
		"BtnTimeInf": 0.0
	}
	for btn_name in time_buttons:
		var btn = find_child(btn_name, true, false) as Button
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_time_button_pressed.bind(time_buttons[btn_name], btn_name))
			
	var kills_buttons = {
		"BtnKills15": 15,
		"BtnKills25": 25,
		"BtnKills40": 40,
		"BtnKills50": 50
	}
	for btn_name in kills_buttons:
		var btn = find_child(btn_name, true, false) as Button
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_kills_button_pressed.bind(kills_buttons[btn_name], btn_name))
			
	var diff_buttons = {
		"BtnDiffEasy": "easy",
		"BtnDiffNormal": "normal",
		"BtnDiffHard": "hard"
	}
	for btn_name in diff_buttons:
		var btn = find_child(btn_name, true, false) as Button
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_diff_button_pressed.bind(diff_buttons[btn_name], btn_name))
			
	var btn_start = find_child("BtnStartMatch", true, false) as Button
	if btn_start and not btn_start.pressed.is_connected(_on_start_match_clicked):
		btn_start.focus_mode = Control.FOCUS_NONE
		btn_start.pressed.connect(_on_start_match_clicked)

	var btn_touch = find_child("BtnToggleTouchControls", true, false) as Button
	if btn_touch and not btn_touch.pressed.is_connected(_on_toggle_touch_clicked):
		btn_touch.focus_mode = Control.FOCUS_NONE
		btn_touch.pressed.connect(_on_toggle_touch_clicked)
		_apply_touch_mode()

	var btn_custom_hud = find_child("BtnCustomizeTouchLayout", true, false) as Button
	if btn_custom_hud and not btn_custom_hud.pressed.is_connected(_on_customize_touch_layout_clicked):
		btn_custom_hud.focus_mode = Control.FOCUS_NONE
		btn_custom_hud.pressed.connect(_on_customize_touch_layout_clicked)
		
	_highlight_selected_mode("BtnModeSingle")
	_set_join_team("red")
	_highlight_selected_time("BtnTime5")
	_highlight_selected_kills("BtnKills25")
	_highlight_selected_diff("BtnDiffNormal")
	_update_setup_summary()

var touch_override_mode: int = 0 # 0 = Auto, 1 = Sempre Ativo, 2 = Desativado

func _on_toggle_touch_clicked() -> void:
	touch_override_mode = (touch_override_mode + 1) % 3
	_apply_touch_mode()
	AudioManager.play("empty_click", 0.0, 1.2)

func _apply_touch_mode() -> void:
	var touch_node = find_child("TouchControls", true, false) as Control
	var btn_touch = find_child("BtnToggleTouchControls", true, false) as Button
	
	var is_mobile_device: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var enable_touch: bool = false
	var status_text: String = ""
	
	match touch_override_mode:
		0:
			enable_touch = is_mobile_device
			status_text = "Auto (%s)" % ("Ativo" if enable_touch else "Oculto no PC")
		1:
			enable_touch = true
			status_text = "Ativo (Teste no PC com Mouse)"
		2:
			enable_touch = false
			status_text = "Desativado"
			
	if touch_node:
		touch_node.force_mobile_test = (touch_override_mode == 1)
		touch_node.set_active(enable_touch)
		
	if btn_touch:
		btn_touch.text = "📱 Controles Touch na Tela: %s" % status_text
		btn_touch.modulate = Color(0.3, 1.0, 0.5) if enable_touch else Color(0.8, 0.8, 0.8)

func _on_customize_touch_layout_clicked() -> void:
	if match_setup_panel:
		match_setup_panel.visible = false
	var touch_node = find_child("TouchControls", true, false) as Control
	if touch_node and touch_node.has_method("start_layout_editor"):
		if not touch_node.editor_closed.is_connected(_on_touch_editor_closed):
			touch_node.editor_closed.connect(_on_touch_editor_closed)
		touch_node.start_layout_editor()

func _on_touch_editor_closed() -> void:
	if match_setup_panel:
		match_setup_panel.visible = true

func _on_mode_button_pressed(mode: String, btn_name: String) -> void:
	current_game_mode = mode
	_highlight_selected_mode(btn_name)
	
	var host_box = find_child("HostNetworkBox", true, false) as VBoxContainer
	var join_box = find_child("JoinNetworkBox", true, false) as VBoxContainer
	var btn_start = find_child("BtnStartMatch", true, false) as Button
	
	if host_box:
		host_box.visible = (mode == "host")
	if join_box:
		join_box.visible = (mode == "join")
		
	if btn_start:
		match mode:
			"single":
				btn_start.text = "▶️ INICIAR PARTIDA OFFLINE"
			"host":
				btn_start.text = "👑 CRIAR SERVIDOR (HOST & JOGAR)"
			"join":
				btn_start.text = "🔗 ENTRAR NO SERVIDOR (JOIN)"
				
	_update_setup_summary()
	AudioManager.play("empty_click", 0.0, 1.2)

func _highlight_selected_mode(active_name: String) -> void:
	var names = ["BtnModeSingle", "BtnModeHost", "BtnModeJoin"]
	for n in names:
		var btn = find_child(n, true, false) as Button
		if btn:
			if n == active_name:
				btn.modulate = Color(0.2, 0.95, 1.0)
			else:
				btn.modulate = Color(0.7, 0.7, 0.7)

func _set_join_team(chosen_team: String) -> void:
	join_team = chosen_team
	var btn_blue = find_child("BtnJoinTeamBlue", true, false) as Button
	var btn_red = find_child("BtnJoinTeamRed", true, false) as Button
	if btn_blue:
		btn_blue.modulate = Color(0.2, 0.6, 1.0) if join_team == "blue" else Color(0.6, 0.6, 0.6)
	if btn_red:
		btn_red.modulate = Color(1.0, 0.3, 0.3) if join_team == "red" else Color(0.6, 0.6, 0.6)

func _on_time_button_pressed(seconds: float, btn_name: String) -> void:
	selected_time_seconds = seconds
	_highlight_selected_time(btn_name)
	_update_setup_summary()
	AudioManager.play("empty_click", 0.0, 1.2)

func _on_kills_button_pressed(kills: int, btn_name: String) -> void:
	selected_target_kills = kills
	_highlight_selected_kills(btn_name)
	_update_setup_summary()
	AudioManager.play("empty_click", 0.0, 1.2)

func _on_diff_button_pressed(diff: String, btn_name: String) -> void:
	selected_difficulty = diff
	_highlight_selected_diff(btn_name)
	_update_setup_summary()
	AudioManager.play("empty_click", 0.0, 1.2)

func _highlight_selected_time(active_name: String) -> void:
	var names = ["BtnTime1", "BtnTime3", "BtnTime5", "BtnTime10", "BtnTimeInf"]
	for n in names:
		var btn = find_child(n, true, false) as Button
		if btn:
			if n == active_name:
				btn.modulate = Color(0.3, 1.0, 0.45)
			else:
				btn.modulate = Color(0.7, 0.7, 0.7)

func _highlight_selected_kills(active_name: String) -> void:
	var names = ["BtnKills15", "BtnKills25", "BtnKills40", "BtnKills50"]
	for n in names:
		var btn = find_child(n, true, false) as Button
		if btn:
			if n == active_name:
				btn.modulate = Color(1.0, 0.6, 0.3)
			else:
				btn.modulate = Color(0.7, 0.7, 0.7)

func _highlight_selected_diff(active_name: String) -> void:
	var names = ["BtnDiffEasy", "BtnDiffNormal", "BtnDiffHard"]
	for n in names:
		var btn = find_child(n, true, false) as Button
		if btn:
			if n == active_name:
				btn.modulate = Color(0.9, 0.4, 1.0)
			else:
				btn.modulate = Color(0.7, 0.7, 0.7)

func _update_setup_summary() -> void:
	if not setup_summary_label:
		setup_summary_label = find_child("SetupSummaryLabel", true, false) as Label
	if setup_summary_label:
		var time_str: String = "Ilimitado" if selected_time_seconds <= 0 else ("%d Minutos" % int(selected_time_seconds / 60))
		var diff_names = {
			"easy": "Recruta (Fácil)",
			"normal": "Soldado (Normal)",
			"hard": "Elite (Veterano)"
		}
		var mode_desc = "Solo Offline"
		if current_game_mode == "host":
			mode_desc = "👑 Servidor Host (LAN + UPnP)"
		elif current_game_mode == "join":
			mode_desc = "🔗 Cliente (Conectar a Host)"
			
		setup_summary_label.text = "Modo: %s | Tempo: %s | Meta: %d Abates | IA: %s" % [
			mode_desc, time_str, selected_target_kills, diff_names.get(selected_difficulty, "Soldado")
		]

func _on_start_match_clicked() -> void:
	match current_game_mode:
		"single":
			close_match_setup()
			start_match_requested.emit(selected_time_seconds, selected_target_kills, selected_difficulty)
		"host":
			close_match_setup()
			var use_upnp: bool = true
			var upnp_check = find_child("HostUpnpCheck", true, false) as CheckBox
			if upnp_check:
				use_upnp = upnp_check.button_pressed
			host_match_requested.emit(7777, use_upnp, selected_time_seconds, selected_target_kills, selected_difficulty)
		"join":
			var ip_edit = find_child("JoinIpEdit", true, false) as LineEdit
			var port_edit = find_child("JoinPortEdit", true, false) as LineEdit
			var name_edit = find_child("JoinNameEdit", true, false) as LineEdit
			
			var ip: String = ip_edit.text.strip_edges() if ip_edit else "127.0.0.1"
			var port: int = port_edit.text.to_int() if port_edit and port_edit.text.to_int() > 0 else 7777
			var p_name: String = name_edit.text.strip_edges() if name_edit and not name_edit.text.strip_edges().is_empty() else "Jogador 2"
			
			set_join_status("Conectando ao servidor %s:%d..." % [ip, port], false)
			join_match_requested.emit(ip, port, p_name, join_team)

## Fecha o painel de setup e captura o cursor
func close_match_setup() -> void:
	is_in_match_setup = false
	if match_setup_panel:
		match_setup_panel.visible = false
	if touch_override_mode == 1 or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Helpers para status de rede no HUD
func set_host_upnp_status(msg: String, is_success: bool) -> void:
	var label = find_child("HostUpnpStatusLabel", true, false) as Label
	if label:
		label.text = msg
		label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.4) if is_success else Color(0.95, 0.85, 0.3))

func set_join_status(msg: String, is_error: bool) -> void:
	var label = find_child("JoinStatusLabel", true, false) as Label
	if label:
		label.text = msg
		label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if is_error else Color(0.4, 0.85, 1.0))
