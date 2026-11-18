extends Node3D

## Configurações do Campeonato 5v5
@export var target_score: int = 25 # Meta de abates para vencer o torneio

@onready var hud: CanvasLayer = $HUD
@onready var player: CharacterBody3D = $Player
@onready var bots_container: Node3D = $Bots

var blue_score: int = 0
var red_score: int = 0
var game_ended: bool = false
var last_player_hp: int = 100

var match_started: bool = false
var match_duration: float = 300.0 # 5 min por padrão (0 = ilimitado)
var match_time_remaining: float = 300.0

const NetworkManagerScript = preload("res://scripts/network_manager.gd")

# Dicionário com estatísticas individuais em tempo real
var combatant_stats: Dictionary = {}
var network_manager: Node = null
var remote_players: Dictionary = {} # peer_id -> Node3D

# Pools de nomes aleatórios para os bots
var available_blue_names: Array[String] = [
	"Viper", "Ghost", "Shadow", "Falcon", "Raptor", "Titan", "Apex", "Specter", "Echo", "Blaze", "Hawk", "Pulse"
]
var available_red_names: Array[String] = [
	"Reaper", "Vortex", "Cobra", "Havoc", "Skull", "Phantom", "Striker", "Venom", "Chaos", "Fury", "Storm", "Onyx"
]

func _ready() -> void:
	InputSetup.ensure_inputs()
	
	_setup_network_manager()
	_setup_random_bot_names()
	_initialize_stats()
	_connect_player()
	_connect_bots()
	
	if hud:
		hud.update_scores(blue_score, red_score)
		hud.update_match_timer(match_time_remaining)
		if not hud.start_match_requested.is_connected(_on_start_match_requested):
			hud.start_match_requested.connect(_on_start_match_requested)
		if hud.has_signal("host_match_requested") and not hud.host_match_requested.is_connected(_on_host_match_requested):
			hud.host_match_requested.connect(_on_host_match_requested)
		if hud.has_signal("join_match_requested") and not hud.join_match_requested.is_connected(_on_join_match_requested):
			hud.join_match_requested.connect(_on_join_match_requested)
		if player:
			hud.update_player_hp(player.current_health, player.max_health)
			
	print("[CAMPEONATO] Aguardando configuração inicial de partida pelo jogador.")

func _physics_process(delta: float) -> void:
	if not match_started or game_ended:
		return
		
	if match_duration > 0:
		match_time_remaining -= delta
		if hud:
			hud.update_match_timer(match_time_remaining)
		if match_time_remaining <= 0.0:
			match_time_remaining = 0.0
			_on_match_time_expired()

## Inicia a partida com os parâmetros escolhidos no painel de configuração
func _on_start_match_requested(time_limit_sec: float, target_kills: int, difficulty: String = "normal") -> void:
	target_score = target_kills
	match_duration = time_limit_sec
	match_time_remaining = time_limit_sec
	match_started = true
	
	var time_desc = "ILIMITADO" if match_duration <= 0 else ("%d MINUTOS" % int(match_duration / 60))
	var diff_labels = {"easy": "RECRUTA", "normal": "SOLDADO", "hard": "VETERANO"}
	var diff_str: String = diff_labels.get(difficulty, "SOLDADO")
	
	if hud:
		hud.set_goal_text("META: %d ABATES | %s | IA: %s" % [target_score, time_desc, diff_str])
		hud.update_match_timer(match_time_remaining if match_duration > 0 else -1)
		
	if player:
		player.match_active = true
		
	if bots_container:
		for bot in bots_container.get_children():
			if "match_active" in bot:
				bot.match_active = true
				if bot.has_method("set_difficulty"):
					bot.set_difficulty(difficulty)
				if bot.has_method("_pick_new_patrol_destination"):
					bot._pick_new_patrol_destination()
					
	AudioManager.play("buy", 1.5, 1.1)
	print("[CAMPEONATO] Campeonato 5v5 iniciado! Duração: %s | Meta: %d abates | Dificuldade IA: %s" % [time_desc, target_score, diff_str])

## Fim de partida por tempo esgotado
func _on_match_time_expired() -> void:
	if game_ended:
		return
	game_ended = true
	
	var winner_team: String
	var reason: String
	if blue_score > red_score:
		winner_team = "blue"
		reason = "TEMPO ESGOTADO! O Time Azul venceu por pontos (%d x %d)!" % [blue_score, red_score]
	elif red_score > blue_score:
		winner_team = "red"
		reason = "TEMPO ESGOTADO! O Time Vermelho venceu por pontos (%d x %d)!" % [red_score, blue_score]
	else:
		winner_team = "draw"
		reason = "TEMPO ESGOTADO! A partida terminou em EMPATE (%d x %d)!" % [blue_score, red_score]
		
	print("[CAMPEONATO] %s" % reason)
	if hud:
		hud.show_game_over(winner_team, blue_score, red_score, reason)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()

## Distribui nomes aleatórios aos bots no início da partida
func _setup_random_bot_names() -> void:
	available_blue_names.shuffle()
	available_red_names.shuffle()
	
	if player:
		player.character_name = "Você"
		
	if bots_container:
		for bot in bots_container.get_children():
			var b_team = bot.get("team")
			if b_team == "blue":
				var chosen_name = available_blue_names.pop_front() if not available_blue_names.is_empty() else "Aliado"
				bot.bot_name = chosen_name
			else:
				var chosen_name = available_red_names.pop_front() if not available_red_names.is_empty() else "Inimigo"
				bot.bot_name = chosen_name
				
			if bot.has_method("_update_info_label"):
				bot._update_info_label()

## Inicializa a tabela de estatísticas de cada participante
func _initialize_stats() -> void:
	combatant_stats.clear()
	
	# Jogador
	if player:
		combatant_stats[player.character_name] = {
			"name": player.character_name,
			"team": player.team,
			"kills": 0,
			"deaths": 0,
			"damage": 0,
			"score": 0,
			"is_player": true
		}
		
	# Bots
	if bots_container:
		for bot in bots_container.get_children():
			var b_name: String = str(bot.get("bot_name"))
			var b_team: String = str(bot.get("team"))
			if b_name.is_empty():
				b_name = bot.name
				
			combatant_stats[b_name] = {
				"name": b_name,
				"team": b_team,
				"kills": 0,
				"deaths": 0,
				"damage": 0,
				"score": 0,
				"is_player": false
			}
			
	print("[CAMPEONATO] Estatísticas inicializadas com %d participantes." % combatant_stats.size())

## Conecta eventos do jogador
func _connect_player() -> void:
	if not player:
		return
		
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)
	if not player.died.is_connected(_on_combatant_died):
		player.died.connect(_on_combatant_died)
	if player.has_signal("damage_dealt_to_self") and not player.damage_dealt_to_self.is_connected(_on_damage_dealt):
		player.damage_dealt_to_self.connect(_on_damage_dealt)
		
	if hud:
		if player.has_signal("money_changed") and not player.money_changed.is_connected(hud.update_player_money):
			player.money_changed.connect(hud.update_player_money)
		if player.has_signal("ammo_changed") and not player.ammo_changed.is_connected(hud.update_player_ammo):
			player.ammo_changed.connect(hud.update_player_ammo)
		if player.has_signal("grenades_changed") and not player.grenades_changed.is_connected(hud.update_player_grenades):
			player.grenades_changed.connect(hud.update_player_grenades)
		if player.has_signal("buy_zone_status_changed") and not player.buy_zone_status_changed.is_connected(hud.update_buy_zone_status):
			player.buy_zone_status_changed.connect(hud.update_buy_zone_status)
		if player.has_signal("aim_changed") and not player.aim_changed.is_connected(hud.update_aim_status):
			player.aim_changed.connect(hud.update_aim_status)
		if player.has_signal("enemy_base_infiltrated") and not player.enemy_base_infiltrated.is_connected(_on_player_enemy_base_infiltrated):
			player.enemy_base_infiltrated.connect(_on_player_enemy_base_infiltrated)

func _on_player_enemy_base_infiltrated(bonus: int) -> void:
	if hud:
		hud.show_event_notification("🚨 INVASÃO DE BASE INIMIGA! BÔNUS: +$%d!" % bonus, Color(1.0, 0.85, 0.2))

## Conecta eventos de todos os bots
func _connect_bots() -> void:
	if not bots_container:
		return
	for bot in bots_container.get_children():
		if bot.has_signal("died") and not bot.died.is_connected(_on_combatant_died):
			bot.died.connect(_on_combatant_died)
		if bot.has_signal("damage_dealt_to_self") and not bot.damage_dealt_to_self.is_connected(_on_damage_dealt):
			bot.damage_dealt_to_self.connect(_on_damage_dealt)

## Contabiliza dano em tempo real para o atacante
func _on_damage_dealt(amount: int, attacker_name: String, _attacker_team: String) -> void:
	if attacker_name in combatant_stats:
		combatant_stats[attacker_name]["damage"] += amount
		combatant_stats[attacker_name]["score"] += amount
		_refresh_hud_scoreboard()

## Atualiza vida do jogador no HUD e efeitos visuais
func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	if hud:
		hud.update_player_hp(current_hp, max_hp)
		if current_hp < last_player_hp:
			hud.trigger_damage_flash()
		elif current_hp > last_player_hp and hud.has_method("trigger_heal_flash"):
			hud.trigger_heal_flash()
	last_player_hp = current_hp

## Processa abates, placar e condição de vitória
func _on_combatant_died(killer_name: String, killer_team: String, victim_name: String, victim_team: String, is_headshot: bool = false) -> void:
	# 1. Registra no Killfeed do HUD
	if hud:
		hud.add_killfeed_entry(killer_name, killer_team, victim_name, victim_team, is_headshot)
		
	# 2. Atualiza estatísticas individuais
	if killer_name in combatant_stats:
		combatant_stats[killer_name]["kills"] += 1
		combatant_stats[killer_name]["score"] += 200 if is_headshot else 150
		if player and killer_name == player.character_name:
			var reward: int = 400 if is_headshot else 300
			player.add_money(reward)
			if is_headshot:
				AudioManager.speak_headshot()
				if hud:
					hud.show_headshot_banner()
			else:
				AudioManager.play("kill", 1.5, 1.0)
		
	if victim_name in combatant_stats:
		combatant_stats[victim_name]["deaths"] += 1
		
	_refresh_hud_scoreboard()
		
	if game_ended:
		return
		
	# 3. Atualiza pontuação das equipes
	if victim_team == "red":
		blue_score += 1
	elif victim_team == "blue":
		red_score += 1
		
	print("[CAMPEONATO] %s [%s] foi eliminado por %s [%s]! Placar: AZUL %d x %d VERMELHO" % [victim_name, victim_team, killer_name, killer_team, blue_score, red_score])
	
	if hud:
		hud.update_scores(blue_score, red_score)
		
	# 4. Checa condição de vitória
	if blue_score >= target_score:
		_end_championship("blue", "META DE %d ABATES ATINGIDA!" % target_score)
	elif red_score >= target_score:
		_end_championship("red", "META DE %d ABATES ATINGIDA!" % target_score)

## Atualiza a tabela do HUD se ela estiver visível
func _refresh_hud_scoreboard() -> void:
	if hud and hud.has_method("refresh_scoreboard"):
		hud.refresh_scoreboard(get_scoreboard_data())

## Retorna os dados ordenados por score/kills para cada equipe
func get_scoreboard_data() -> Dictionary:
	var blue_team: Array = []
	var red_team: Array = []
	
	for entry in combatant_stats.values():
		if entry["team"] == "blue":
			blue_team.append(entry.duplicate())
		else:
			red_team.append(entry.duplicate())
			
	var sort_func = func(a, b):
		if a["score"] == b["score"]:
			return a["kills"] > b["kills"]
		return a["score"] > b["score"]
		
	blue_team.sort_custom(sort_func)
	red_team.sort_custom(sort_func)
	
	return {
		"blue_team": blue_team,
		"red_team": red_team,
		"blue_score": blue_score,
		"red_score": red_score,
		"target_score": target_score
	}

func _end_championship(winner_team: String, custom_reason: String = "") -> void:
	game_ended = true
	match_started = false
	
	# 1. Todos devem parar completamente (Jogador e Bots)
	if player:
		player.match_active = false
		player.velocity = Vector3.ZERO
		
	if bots_container:
		for bot in bots_container.get_children():
			if "match_active" in bot:
				bot.match_active = false
				bot.velocity = Vector3.ZERO
				
	# 2. Libera o cursor do mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# 3. Atualiza e exibe o placar detalhado completo
	_refresh_hud_scoreboard()
	
	print("[CAMPEONATO] FIM DE PARTIDA! Vencedor: Time %s! %s" % [winner_team.to_upper(), custom_reason])
	if hud:
		hud.show_game_over(winner_team, blue_score, red_score, custom_reason)

## =============================================================================
## SISTEMA DE REDE E MULTIPLAYER (HOST / LAN / UPNP / CLIENT)
## =============================================================================

func _setup_network_manager() -> void:
	network_manager = NetworkManagerScript.new()
	network_manager.name = "NetworkManager"
	add_child(network_manager)
	
	network_manager.server_started.connect(_on_server_started)
	network_manager.upnp_finished.connect(_on_upnp_finished)
	network_manager.client_connected_ok.connect(_on_client_connected_ok)
	network_manager.client_connection_failed.connect(_on_client_connection_failed)
	network_manager.server_disconnected_msg.connect(_on_server_disconnected)
	network_manager.peer_joined.connect(_on_peer_joined)
	network_manager.peer_left.connect(_on_peer_left)

func _on_host_match_requested(port: int, use_upnp: bool, time_limit_sec: float, target_kills: int, difficulty: String) -> void:
	var result = network_manager.host_server(port, use_upnp, "Host (Você)", "blue")
	if not result.get("success", false):
		if hud:
			hud.show_event_notification("❌ Erro ao criar servidor: %s" % result.get("message", ""), Color(1.0, 0.3, 0.3))
		return
		
	if player:
		player.setup_multiplayer(1, "Host (Você)", "blue", false)
		
	_on_start_match_requested(time_limit_sec, target_kills, difficulty)
	if hud:
		hud.show_event_notification("👑 Servidor Local Aberto na porta %d! Aguardando amigos..." % port, Color(0.3, 1.0, 0.45))

func _on_server_started(local_ip: String, port: int) -> void:
	print("[REDE] Servidor iniciado com sucesso no IP Local: %s:%d" % [local_ip, port])

func _on_upnp_finished(success: bool, ext_ip: String, message: String) -> void:
	if hud:
		hud.set_host_upnp_status(message, success)
		if success:
			hud.show_event_notification("🌐 UPnP Concluído: Porta %d Aberta! IP Público: %s" % [network_manager.current_port, ext_ip], Color(0.2, 1.0, 0.5))
		else:
			hud.show_event_notification("ℹ️ UPnP indisponível. Para jogar na mesma casa/Wi-Fi use o IP: %s" % network_manager.local_ip_address, Color(1.0, 0.85, 0.2))

func _on_join_match_requested(ip: String, port: int, player_name: String, player_team: String) -> void:
	network_manager.join_server(ip, port, player_name, player_team)

func _on_client_connected_ok() -> void:
	if hud:
		hud.close_match_setup()
		hud.show_event_notification("✅ Conectado com sucesso ao Servidor!", Color(0.2, 1.0, 0.5))
		
	var my_id: int = multiplayer.get_unique_id()
	var my_data: Dictionary = network_manager.lobby_players.get(my_id, {"name": "Jogador", "team": "red"})
	var p_name: String = my_data.get("name", "Jogador")
	var p_team: String = my_data.get("team", "red")
	
	if player:
		player.setup_multiplayer(my_id, p_name, p_team, false)
		if p_team == "red":
			player.spawn_position = Vector3(randf_range(-3.0, 3.0), 1.0, -64.0)
			player.global_position = player.spawn_position
			player.rotation.y = deg_to_rad(180)
		else:
			player.spawn_position = Vector3(randf_range(-3.0, 3.0), 1.0, 64.0)
			player.global_position = player.spawn_position
			
		# Atualiza registro de stats para o novo jogador
		if combatant_stats.has("Você"):
			combatant_stats.erase("Você")
		combatant_stats[p_name] = {
			"name": p_name,
			"team": p_team,
			"kills": 0,
			"deaths": 0,
			"damage": 0,
			"score": 0,
			"is_player": true
		}
		
	_replace_bot_with_player(p_team, p_name)
	_on_start_match_requested(300.0, 25, "normal")

func _on_client_connection_failed(reason: String) -> void:
	if hud:
		hud.set_join_status(reason, true)
		hud.show_event_notification("❌ %s" % reason, Color(1.0, 0.35, 0.35))

func _on_server_disconnected() -> void:
	if hud:
		hud.show_event_notification("🔌 Desconectado do servidor pelo Host.", Color(1.0, 0.4, 0.4))

func _on_peer_joined(peer_id: int, player_data: Dictionary) -> void:
	var my_id = multiplayer.get_unique_id()
	if peer_id == my_id:
		return
		
	if remote_players.has(peer_id):
		return
		
	var p_name: String = str(player_data.get("name", "Amigo"))
	var p_team: String = str(player_data.get("team", "red"))
	
	var player_scene = preload("res://scenes/player.tscn")
	var remote_p = player_scene.instantiate() as CharacterBody3D
	remote_p.name = "RemotePlayer_%d" % peer_id
	add_child(remote_p)
	
	remote_p.setup_multiplayer(peer_id, p_name, p_team, true)
	if p_team == "red":
		remote_p.spawn_position = Vector3(randf_range(-3.0, 3.0), 1.0, -64.0)
	else:
		remote_p.spawn_position = Vector3(randf_range(-3.0, 3.0), 1.0, 64.0)
		
	remote_p.global_position = remote_p.spawn_position
	remote_p.match_active = true
	
	remote_p.died.connect(_on_combatant_died)
	remote_p.damage_dealt_to_self.connect(_on_damage_dealt)
	
	remote_players[peer_id] = remote_p
	
	combatant_stats[p_name] = {
		"name": p_name,
		"team": p_team,
		"kills": 0,
		"deaths": 0,
		"damage": 0,
		"score": 0,
		"is_player": true
	}
	
	_replace_bot_with_player(p_team, p_name)
	
	if hud:
		hud.show_event_notification("👥 %s [%s] entrou na partida!" % [p_name, p_team.to_upper()], Color(0.2, 0.95, 1.0))
		_refresh_hud_scoreboard()
		
	if network_manager and network_manager.is_host:
		rpc_id(peer_id, "rpc_sync_match_state", match_duration, match_time_remaining, target_score, blue_score, red_score)

func _on_peer_left(peer_id: int) -> void:
	if not remote_players.has(peer_id):
		return
		
	var remote_p = remote_players[peer_id]
	var p_team: String = "red"
	var p_name: String = "Jogador"
	if is_instance_valid(remote_p):
		p_team = remote_p.team
		p_name = remote_p.character_name
		remote_p.queue_free()
		
	remote_players.erase(peer_id)
	
	if combatant_stats.has(p_name):
		combatant_stats.erase(p_name)
		
	_restore_bot_for_team(p_team)
	
	if hud:
		hud.show_event_notification("🚪 %s desconectou da partida." % p_name, Color(1.0, 0.6, 0.3))
		_refresh_hud_scoreboard()

## Substitui um bot do time correspondente para manter o equilíbrio 5v5
func _replace_bot_with_player(p_team: String, p_name: String) -> void:
	if not bots_container:
		return
	for bot in bots_container.get_children():
		if bot.visible and bot.get("team") == p_team:
			bot.visible = false
			bot.set_physics_process(false)
			bot.process_mode = Node.PROCESS_MODE_DISABLED
			var b_name = str(bot.get("bot_name"))
			if combatant_stats.has(b_name):
				combatant_stats.erase(b_name)
			print("[CAMPEONATO] Bot %s substituído pelo jogador %s no time %s." % [b_name, p_name, p_team])
			break

## Reativa um bot caso um jogador humano saia da partida
func _restore_bot_for_team(p_team: String) -> void:
	if not bots_container:
		return
	for bot in bots_container.get_children():
		if not bot.visible and bot.get("team") == p_team:
			bot.visible = true
			bot.set_physics_process(true)
			bot.process_mode = Node.PROCESS_MODE_INHERIT
			var b_name = str(bot.get("bot_name"))
			combatant_stats[b_name] = {
				"name": b_name,
				"team": p_team,
				"kills": 0,
				"deaths": 0,
				"damage": 0,
				"score": 0,
				"is_player": false
			}
			print("[CAMPEONATO] Bot %s reativado no time %s." % [b_name, p_team])
			break

@rpc("any_peer")
func rpc_sync_match_state(dur: float, remaining: float, target: int, b_score: int, r_score: int) -> void:
	match_duration = dur
	match_time_remaining = remaining
	target_score = target
	blue_score = b_score
	red_score = r_score
	
	if hud:
		hud.update_scores(blue_score, red_score)
		hud.update_match_timer(match_time_remaining if match_duration > 0 else -1)
		var time_desc = "ILIMITADO" if match_duration <= 0 else ("%d MINUTOS" % int(match_duration / 60))
		hud.set_goal_text("META: %d ABATES | %s" % [target_score, time_desc])
	_refresh_hud_scoreboard()
