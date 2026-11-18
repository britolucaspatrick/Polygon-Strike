extends CharacterBody3D

## Sinais de evento do bot
signal died(killer_name: String, killer_team: String, victim_name: String, victim_team: String, is_headshot: bool)
signal health_changed(new_hp: int, max_hp: int)
signal damage_dealt_to_self(amount: int, attacker_name: String, attacker_team: String)

enum State { PATROL, COMBAT, RETREAT, DEAD }

## Configurações do Bot
@export var team: String = "red" # "blue" ou "red"
@export var bot_name: String = "Bot"
@export var max_health: int = 100
@export var walk_speed: float = 6.5
@export var combat_speed: float = 7.5
@export var damage: int = 12
@export var fire_rate: float = 0.26
@export var sight_range: float = 85.0

## Multiplicadores de Dano por Parte do Corpo
const MULT_HEAD: float = 2.2
const MULT_CHEST: float = 1.0
const MULT_LEGS: float = 0.7

var current_health: int = 100
var current_state: State = State.PATROL
var target_enemy: Node3D = null
var match_active: bool = false

# Dificuldade da IA e parâmetros táticos (Nível 1)
var bot_difficulty: String = "normal"
var reaction_time: float = 0.20
var reaction_timer: float = 0.0
var spread_multiplier: float = 1.0
var bot_money: int = 500
var current_weapon: String = "rifle"
var current_lane: String = "center"
var available_lanes: Array[String] = ["center", "west", "east"]
var cover_points: Array[Vector3] = []

# Timers e controles de navegação
var can_shoot: bool = true
var target_nav_point: Vector3 = Vector3.ZERO
var repath_timer: float = 0.0
var strafe_direction: float = 1.0
var strafe_timer: float = 0.0
var jump_cooldown: float = 0.0

var spawn_position: Vector3 = Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Referências aos nós
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_chest: MeshInstance3D = $VisualModel/ChestMesh
@onready var mesh_head: MeshInstance3D = $VisualModel/HeadMesh
@onready var mesh_legs: MeshInstance3D = $VisualModel/LegsMesh
@onready var head_node: Node3D = $Head
@onready var weapon_holder: Node3D = $Head/WeaponHolder
@onready var muzzle: Marker3D = $Head/WeaponHolder/Muzzle
@onready var shoot_timer: Timer = $ShootTimer
@onready var respawn_timer: Timer = $RespawnTimer
@onready var info_label: Label3D = $InfoLabel

var team_main_mat: StandardMaterial3D
var team_dark_mat: StandardMaterial3D
var hit_tween: Tween

func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	
	collision_layer = 2
	collision_mask = 3
	
	# Inicializa pontos de cobertura tática da arena
	cover_points = [
		Vector3(-18, 1.5, 30), Vector3(18, 1.5, 30),
		Vector3(-18, 1.5, -30), Vector3(18, 1.5, -30),
		Vector3(-42, 1.5, 26), Vector3(-42, 1.5, -26),
		Vector3(42, 1.5, 26), Vector3(42, 1.5, -26),
		Vector3(0, 1.5, 50), Vector3(0, 1.5, -50),
		Vector3(-16, 1.5, 52), Vector3(16, 1.5, 52),
		Vector3(-16, 1.5, -52), Vector3(16, 1.5, -52)
	]
	
	current_lane = available_lanes[randi() % available_lanes.size()]
	
	_setup_team_appearance()
	_update_info_label()
	
	shoot_timer.wait_time = fire_rate
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(func(): can_shoot = true)
	
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn)
	
	_pick_new_patrol_destination()

## Aplica os parâmetros de dificuldade da IA
func set_difficulty(diff: String) -> void:
	bot_difficulty = diff
	match diff:
		"easy":
			reaction_time = 0.38
			spread_multiplier = 1.6
			damage = 8
			fire_rate = 0.32
			combat_speed = 6.2
			walk_speed = 5.5
		"hard":
			reaction_time = 0.06
			spread_multiplier = 0.42
			damage = 16
			fire_rate = 0.18
			combat_speed = 8.5
			walk_speed = 7.0
		_: # normal
			reaction_time = 0.20
			spread_multiplier = 1.0
			damage = 12
			fire_rate = 0.26
			combat_speed = 7.5
			walk_speed = 6.5
			
	if shoot_timer:
		shoot_timer.wait_time = fire_rate

func _physics_process(delta: float) -> void:
	if not match_active or current_state == State.DEAD:
		return
		
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	jump_cooldown -= delta
	
	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.COMBAT:
			_process_combat(delta)
		State.RETREAT:
			_process_retreat(delta)
			
	move_and_slide()
	
	# Pula se colidir com paredes ou obstáculos no chão
	if is_on_wall() and is_on_floor() and jump_cooldown <= 0:
		velocity.y = 5.0
		jump_cooldown = 0.9
		target_nav_point += transform.basis.x * (randf_range(-8.0, 8.0))

## Define cores e visual do time para as 3 partes do corpo
func _setup_team_appearance() -> void:
	team_main_mat = StandardMaterial3D.new()
	team_dark_mat = StandardMaterial3D.new()
	
	if team == "blue":
		team_main_mat.albedo_color = Color(0.2, 0.5, 0.95)
		team_dark_mat.albedo_color = Color(0.12, 0.25, 0.5)
		info_label.modulate = Color(0.4, 0.8, 1.0)
	else:
		team_main_mat.albedo_color = Color(0.92, 0.22, 0.22)
		team_dark_mat.albedo_color = Color(0.5, 0.12, 0.12)
		info_label.modulate = Color(1.0, 0.45, 0.45)
		
	team_main_mat.roughness = 0.4
	team_dark_mat.roughness = 0.6
	
	if mesh_chest:
		mesh_chest.material_override = team_main_mat
	if mesh_head:
		mesh_head.material_override = team_main_mat
	if mesh_legs:
		mesh_legs.material_override = team_dark_mat

func _update_info_label() -> void:
	if info_label:
		info_label.text = "%s\nHP: %d" % [bot_name, current_health]

## Estado de Patrulha / Movimento no mapa por rotas táticas (Lanes)
func _process_patrol(delta: float) -> void:
	_scan_for_enemies()
	if target_enemy != null:
		reaction_timer = reaction_time
		current_state = State.COMBAT
		return
		
	repath_timer -= delta
	if repath_timer <= 0 or global_position.distance_to(target_nav_point) < 3.5:
		_pick_new_patrol_destination()
		
	var dir := (target_nav_point - global_position)
	dir.y = 0
	if dir.length() > 0.5:
		dir = dir.normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		
		var target_rotation_y := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_rotation_y, 7.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed * delta * 2)
		velocity.z = move_toward(velocity.z, 0, walk_speed * delta * 2)

## Escolhe pontos para patrulhar avançando pela rota tática (Centro, Flanco Oeste ou Flanco Leste)
func _pick_new_patrol_destination() -> void:
	repath_timer = randf_range(3.2, 5.5)
	var forward_z: float = randf_range(-15.0, -48.0) if team == "blue" else randf_range(15.0, 48.0)
	
	match current_lane:
		"west":
			target_nav_point = Vector3(randf_range(-46.0, -38.0), 1.0, forward_z)
		"east":
			target_nav_point = Vector3(randf_range(38.0, 46.0), 1.0, forward_z)
		_: # center
			target_nav_point = Vector3(randf_range(-14.0, 14.0), 1.0, forward_z)

## Estado de Combate Tático (Uso de Cobertura, Strafing e Disparos Inteligentes)
func _process_combat(delta: float) -> void:
	if not is_instance_valid(target_enemy) or not _is_target_alive(target_enemy):
		target_enemy = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
		return
		
	# Tática de Sobrevivência: Se a vida estiver crítica (<= 35 HP), recua imediatamente para a base
	if current_health <= 35:
		current_state = State.RETREAT
		return
		
	var dist := global_position.distance_to(target_enemy.global_position)
	if dist > sight_range:
		target_enemy = null
		current_state = State.PATROL
		return
		
	var aim_target_pos := target_enemy.global_position + Vector3(0, 1.4, 0)
	var dir_to_enemy := (aim_target_pos - global_position).normalized()
	dir_to_enemy.y = 0
	
	var body_target_rot_y := atan2(-dir_to_enemy.x, -dir_to_enemy.z)
	rotation.y = lerp_angle(rotation.y, body_target_rot_y, 10.0 * delta)
	
	strafe_timer -= delta
	if strafe_timer <= 0:
		strafe_direction = -1.0 if randf() > 0.5 else 1.0
		strafe_timer = randf_range(0.6, 1.5)
		
	var move_vector := Vector3.ZERO
	move_vector += transform.basis.x * (strafe_direction * combat_speed * 0.75)
	
	# Busca por cobertura próxima se a vida estiver abaixo de 60 HP
	if current_health < 60:
		var best_cover := _get_best_cover_point(target_enemy.global_position)
		if best_cover != Vector3.ZERO and global_position.distance_to(best_cover) > 1.5:
			var to_cover := (best_cover - global_position).normalized()
			move_vector = move_vector.lerp(to_cover * combat_speed, 0.45)
	else:
		if dist > 26.0:
			move_vector -= transform.basis.z * (combat_speed * 0.8) # aproxima
		elif dist < 9.0:
			move_vector += transform.basis.z * (combat_speed * 0.8) # recua
		
	velocity.x = move_vector.x
	velocity.z = move_vector.z
	
	reaction_timer -= delta
	if reaction_timer <= 0 and _has_line_of_sight(target_enemy):
		_perform_shot(aim_target_pos)
	elif not _has_line_of_sight(target_enemy):
		target_nav_point = target_enemy.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		var fl_dir := (target_nav_point - global_position).normalized()
		velocity.x = fl_dir.x * combat_speed
		velocity.z = fl_dir.z * combat_speed

## Encontra o melhor ponto de cobertura para quebrar linha de visão com o inimigo
func _get_best_cover_point(enemy_pos: Vector3) -> Vector3:
	var best_pt := Vector3.ZERO
	var min_cost: float = 99999.0
	for cp in cover_points:
		var d_to_bot := global_position.distance_to(cp)
		if d_to_bot < 25.0:
			var d_to_enemy := enemy_pos.distance_to(cp)
			# Dá preferência a coberturas próximas do bot e protegidas
			var cost := d_to_bot - (d_to_enemy * 0.3)
			if cost < min_cost:
				min_cost = cost
				best_pt = cp
	return best_pt

## Estado de Recuo Tático para a Base (Cura e Reabastecimento)
func _process_retreat(delta: float) -> void:
	var base_z: float = 55.0 if team == "blue" else -55.0
	target_nav_point = Vector3(clamp(global_position.x, -20.0, 20.0), 0.5, base_z)
	
	var dir := (target_nav_point - global_position)
	dir.y = 0
	if dir.length() > 0.5:
		var move_dir := dir.normalized()
		velocity.x = move_dir.x * (combat_speed * 1.15)
		velocity.z = move_dir.z * (combat_speed * 1.15)
		var target_rot := atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 8.0 * delta)
	else:
		velocity.x = 0
		velocity.z = 0
		
	# Checa se entrou na zona segura da base
	var in_base: bool = (team == "blue" and global_position.z > 44.0) or (team == "red" and global_position.z < -44.0)
	if in_base:
		if current_health < max_health:
			current_health = max_health
			_update_info_label()
			AudioManager.play_spatial("heal", global_position, -4.0, 1.0, 50.0)
		_try_buy_weapons()
		current_state = State.PATROL
		current_lane = available_lanes[randi() % available_lanes.size()]
		_pick_new_patrol_destination()

## Audição Tática: Reage a passos próximos e estampidos de disparos
func hear_sound(sound_pos: Vector3, sound_intensity: float = 1.0) -> void:
	if not match_active or current_state == State.DEAD:
		return
	if current_state == State.PATROL:
		var dist := global_position.distance_to(sound_pos)
		if dist < (45.0 * sound_intensity):
			var sound_dir := (sound_pos - global_position).normalized()
			sound_dir.y = 0
			if sound_dir.length() > 0.1:
				rotation.y = atan2(-sound_dir.x, -sound_dir.z)
			target_nav_point = sound_pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			repath_timer = 2.5
			_scan_for_enemies()

## Sistema de Compra de Armas Dinâmico da IA
func _try_buy_weapons() -> void:
	if bot_money >= 3000 and current_weapon != "lmg":
		current_weapon = "lmg"
		damage = 18 if bot_difficulty == "hard" else (14 if bot_difficulty == "normal" else 10)
		fire_rate = 0.14
		_update_weapon_mesh(Vector3(0.11, 0.16, 0.72), Color(0.15, 0.15, 0.18))
	elif bot_money >= 2000 and current_weapon != "rifle" and current_weapon != "lmg":
		current_weapon = "rifle"
		damage = 15 if bot_difficulty == "hard" else (12 if bot_difficulty == "normal" else 8)
		fire_rate = 0.20
		_update_weapon_mesh(Vector3(0.09, 0.14, 0.65), Color(0.25, 0.28, 0.22))
	elif bot_money >= 1200 and current_weapon == "pistol":
		current_weapon = "smg"
		damage = 11 if bot_difficulty == "hard" else (8 if bot_difficulty == "normal" else 6)
		fire_rate = 0.11
		_update_weapon_mesh(Vector3(0.09, 0.12, 0.52), Color(0.18, 0.25, 0.3))
		
	if shoot_timer:
		shoot_timer.wait_time = fire_rate

func _update_weapon_mesh(mesh_sz: Vector3, mesh_col: Color) -> void:
	var gun_mesh_node = weapon_holder.get_node_or_null("GunMesh") as MeshInstance3D
	if gun_mesh_node:
		var bm := BoxMesh.new()
		bm.size = mesh_sz
		gun_mesh_node.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mesh_col
		gun_mesh_node.material_override = mat

## Verifica se há visão desobstruída (sem paredes bloqueando)
func _has_line_of_sight(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var space_state := get_world_3d().direct_space_state
	var from_pos := global_position + Vector3(0, 1.4, 0)
	var to_pos := target.global_position + Vector3(0, 1.3, 0)
	
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [self]
	query.collision_mask = 1 # Testa contra cenário
	
	var result := space_state.intersect_ray(query)
	return result.is_empty()

## Executa disparo com cálculo de dispersão calibrado pela dificuldade
func _perform_shot(target_pos: Vector3) -> void:
	if not can_shoot:
		return
		
	can_shoot = false
	shoot_timer.start(fire_rate)
	
	# Som espacial 3D de disparo do bot pelo mapa baseado na arma
	var snd = "shoot_smg" if current_weapon == "smg" else ("shoot_magnum" if current_weapon == "magnum" else "shoot_rifle")
	AudioManager.play_spatial(snd, muzzle.global_position, -2.0, randf_range(0.92, 1.08), 85.0)
	
	# Alerta combatentes próximos sobre o disparo
	_alert_nearby_bots(muzzle.global_position, 1.0)
	
	var from_pos: Vector3 = muzzle.global_position
	var dist := global_position.distance_to(target_pos)
	
	var base_spread: float = 0.045 * spread_multiplier
	var spread := Vector3(
		randf_range(-base_spread, base_spread),
		randf_range(-base_spread, base_spread),
		randf_range(-base_spread, base_spread)
	) * dist
	
	var final_aim_pos := target_pos + spread
	var shoot_dir := (final_aim_pos - from_pos).normalized()
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from_pos, from_pos + shoot_dir * 100.0)
	query.exclude = [self]
	query.collision_mask = 3 # Colide com cenário (1) e combatentes (2)
	
	var result := space_state.intersect_ray(query)
	var hit_pos: Vector3 = from_pos + shoot_dir * 60.0
	
	if not result.is_empty():
		hit_pos = result.position
		var hit_collider = result.collider
		if hit_collider and hit_collider.has_method("take_damage"):
			hit_collider.take_damage(damage, bot_name, team, hit_pos)
			bot_money += 15 # Ganha dinheiro ao acertar disparos
			
	_spawn_tracer_line(from_pos, hit_pos)
	_apply_weapon_recoil()

func _alert_nearby_bots(origin: Vector3, intensity: float) -> void:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c != self and is_instance_valid(c) and c.has_method("hear_sound"):
			c.hear_sound(origin, intensity)

func _apply_weapon_recoil() -> void:
	var recoil_tween := create_tween()
	recoil_tween.tween_property(weapon_holder, "position:z", 0.08, 0.04)
	recoil_tween.tween_property(weapon_holder, "position:z", 0.0, 0.12)

func _spawn_tracer_line(start_point: Vector3, end_point: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh
	
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(0.3, 0.6, 1.0) if team == "blue" else Color(1.0, 0.35, 0.2)
	mesh_instance.material_override = tracer_mat
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start_point)
	immediate_mesh.surface_add_vertex(end_point)
	immediate_mesh.surface_end()
	
	get_tree().root.add_child(mesh_instance)
	
	var tween := mesh_instance.create_tween()
	tween.tween_property(tracer_mat, "albedo_color:a", 0.0, 0.06)
	tween.tween_callback(mesh_instance.queue_free)

func _scan_for_enemies() -> void:
	var combatants = get_tree().get_nodes_in_group("combatants")
	var closest_dist: float = sight_range
	var best_candidate: Node3D = null
	
	for c in combatants:
		if c == self or not is_instance_valid(c):
			continue
		if "team" in c and c.team != self.team and _is_target_alive(c):
			var d: float = global_position.distance_to(c.global_position)
			if d < closest_dist and _has_line_of_sight(c):
				closest_dist = d
				best_candidate = c
					
	if best_candidate != null:
		target_enemy = best_candidate

func _is_target_alive(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if "current_health" in target and target.current_health <= 0:
		return false
	if "is_dead" in target and target.is_dead:
		return false
	return true

## Recebe dano com cálculo por parte do corpo (Cabeça, Peito, Pernas)
func take_damage(base_amount: int, attacker_name: String = "Alguém", attacker_team: String = "", hit_point: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.DEAD:
		return
	if attacker_team == self.team:
		return
		
	# Calcula a altura relativa do impacto em relação à base do bot (0.0m a 1.9m)
	var relative_y: float = 1.0
	if hit_point != Vector3.ZERO:
		relative_y = hit_point.y - global_position.y
		
	var multiplier: float = MULT_CHEST
	var hit_part_name: String = "PEITO"
	var number_color: Color = Color(1.0, 0.9, 0.9)
	var is_headshot: bool = false
	
	if relative_y >= 1.52:
		multiplier = MULT_HEAD
		hit_part_name = "HEADSHOT!"
		number_color = Color(1.0, 0.2, 0.2)
		is_headshot = true
	elif relative_y < 0.57:
		multiplier = MULT_LEGS
		hit_part_name = "PERNAS"
		number_color = Color(0.8, 0.8, 0.8)
		
	var final_damage: int = int(round(base_amount * multiplier))
	current_health = max(0, current_health - final_damage)
	damage_dealt_to_self.emit(final_damage, attacker_name, attacker_team)
	
	# Exibe número flutuante de dano no mundo 3D
	_spawn_damage_indicator(final_damage, hit_part_name, number_color, hit_point)
	
	health_changed.emit(current_health, max_health)
	_update_info_label()
	_flash_hit()
	
	# Se atacado por inimigo que não estava no foco, vira para ele
	if target_enemy == null:
		var attacker = _find_attacker_by_name(attacker_name)
		if attacker:
			target_enemy = attacker
			current_state = State.COMBAT
			
	if current_health <= 0:
		_die(attacker_name, attacker_team, is_headshot)

## Cria indicador flutuante 3D de dano (Damage Number)
func _spawn_damage_indicator(damage_dealt: int, part_text: String, color: Color, hit_point: Vector3) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32 if part_text == "HEADSHOT!" else 24
	label.outline_size = 6
	label.modulate = color
	label.text = "-%d %s" % [damage_dealt, part_text]
	
	var spawn_pos = hit_point if hit_point != Vector3.ZERO else (global_position + Vector3(0, 1.8, 0))
	label.global_position = spawn_pos + Vector3(0, 0.3, 0)
	
	get_tree().root.add_child(label)
	
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.8, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tween.tween_callback(label.queue_free)

func _find_attacker_by_name(a_name: String) -> Node3D:
	for c in get_tree().get_nodes_in_group("combatants"):
		if ("bot_name" in c and c.bot_name == a_name) or ("character_name" in c and c.character_name == a_name):
			return c
	return null

func _flash_hit() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
		
	hit_tween = create_tween()
	var orig_color = Color(0.2, 0.5, 0.95) if team == "blue" else Color(0.92, 0.22, 0.22)
	hit_tween.tween_property(team_main_mat, "albedo_color", Color.WHITE, 0.05)
	hit_tween.tween_property(team_main_mat, "albedo_color", orig_color, 0.12)

## Lógica de morte
func _die(killer_name: String, killer_team: String, is_headshot: bool = false) -> void:
	current_state = State.DEAD
	died.emit(killer_name, killer_team, bot_name, team, is_headshot)
	
	collision_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	
	var death_tween := create_tween()
	death_tween.tween_property($VisualModel, "scale", Vector3(1.0, 0.1, 1.0), 0.2)
	death_tween.parallel().tween_property(info_label, "modulate:a", 0.0, 0.2)
	
	respawn_timer.start(2.8)

## Renasce o bot na base de sua equipe
func _respawn() -> void:
	current_health = max_health
	current_state = State.PATROL
	target_enemy = null
	
	global_position = spawn_position + Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-3.0, 3.0))
	velocity = Vector3.ZERO
	
	$VisualModel.scale = Vector3.ONE
	info_label.modulate.a = 1.0
	_update_info_label()
	
	# Verifica se compra armas melhores com o saldo acumulado
	_try_buy_weapons()
	
	collision_shape.set_deferred("disabled", false)
	current_lane = available_lanes[randi() % available_lanes.size()]
	_pick_new_patrol_destination()
