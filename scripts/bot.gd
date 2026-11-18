extends CharacterBody3D

## Sinais de evento do bot
signal died(killer_name: String, killer_team: String, victim_name: String, victim_team: String)
signal health_changed(new_hp: int, max_hp: int)
signal damage_dealt_to_self(amount: int, attacker_name: String, attacker_team: String)

enum State { PATROL, COMBAT, DEAD }

## Configurações do Bot
@export var team: String = "red" # "blue" ou "red"
@export var bot_name: String = "Bot"
@export var max_health: int = 100
@export var walk_speed: float = 6.5
@export var combat_speed: float = 7.5
@export var damage: int = 10
@export var fire_rate: float = 0.28
@export var sight_range: float = 140.0

## Multiplicadores de Dano por Parte do Corpo
# 20% Topo: Cabeça (1.52m a 1.90m) -> 2.2x
# 50% Meio: Peito/Tronco (0.57m a 1.52m) -> 1.0x
# 30% Base: Pernas (0.00m a 0.57m) -> 0.7x
const MULT_HEAD: float = 2.2
const MULT_CHEST: float = 1.0
const MULT_LEGS: float = 0.7

var current_health: int = 100
var current_state: State = State.PATROL
var target_enemy: Node3D = null
var match_active: bool = false

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
	
	_setup_team_appearance()
	_update_info_label()
	
	shoot_timer.wait_time = fire_rate
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(func(): can_shoot = true)
	
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn)
	
	_pick_new_patrol_destination()

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

## Estado de Patrulha / Movimento no mapa
func _process_patrol(delta: float) -> void:
	_scan_for_enemies()
	if target_enemy != null:
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

## Escolhe pontos para patrulhar avançando pelo mapa ampliado
func _pick_new_patrol_destination() -> void:
	repath_timer = randf_range(3.5, 6.5)
	# Avança rumo ao campo inimigo
	var forward_z: float = randf_range(-40.0, -115.0) if team == "blue" else randf_range(40.0, 115.0)
	target_nav_point = Vector3(
		randf_range(-85.0, 85.0),
		0.5,
		forward_z
	)

## Estado de Combate
func _process_combat(delta: float) -> void:
	if not is_instance_valid(target_enemy) or not _is_target_alive(target_enemy):
		target_enemy = null
		current_state = State.PATROL
		_pick_new_patrol_destination()
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
		strafe_timer = randf_range(0.8, 1.8)
		
	var move_vector := Vector3.ZERO
	move_vector += transform.basis.x * (strafe_direction * combat_speed * 0.75)
	
	if dist > 26.0:
		move_vector -= transform.basis.z * (combat_speed * 0.8) # aproxima
	elif dist < 9.0:
		move_vector += transform.basis.z * (combat_speed * 0.8) # recua
		
	velocity.x = move_vector.x
	velocity.z = move_vector.z
	
	if _has_line_of_sight(target_enemy):
		_perform_shot(aim_target_pos)
	else:
		target_nav_point = target_enemy.global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		var fl_dir := (target_nav_point - global_position).normalized()
		velocity.x = fl_dir.x * combat_speed
		velocity.z = fl_dir.z * combat_speed

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

## Executa disparo com cálculo de dispersão
func _perform_shot(target_pos: Vector3) -> void:
	if not can_shoot:
		return
		
	can_shoot = false
	shoot_timer.start(fire_rate)
	
	# Som espacial 3D de disparo do bot pelo mapa
	AudioManager.play_spatial("shoot_rifle", muzzle.global_position, -2.0, randf_range(0.92, 1.08), 85.0)
	
	var from_pos: Vector3 = muzzle.global_position
	var dist := global_position.distance_to(target_pos)
	
	var spread := Vector3(
		randf_range(-0.05, 0.05),
		randf_range(-0.05, 0.05),
		randf_range(-0.05, 0.05)
	) * dist
	
	var final_aim_pos := target_pos + spread
	var shoot_dir := (final_aim_pos - from_pos).normalized()
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from_pos, from_pos + shoot_dir * 160.0)
	query.exclude = [self]
	query.collision_mask = 3 # Colide com cenário (1) e combatentes (2)
	
	var result := space_state.intersect_ray(query)
	var hit_pos: Vector3 = from_pos + shoot_dir * 60.0
	
	if not result.is_empty():
		hit_pos = result.position
		var hit_collider = result.collider
		if hit_collider and hit_collider.has_method("take_damage"):
			hit_collider.take_damage(damage, bot_name, team, hit_pos)
			
	_spawn_tracer_line(from_pos, hit_pos)
	_apply_weapon_recoil()

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
	var relative_y: float = 1.0 # Padrão caso não seja passado ponto
	if hit_point != Vector3.ZERO:
		relative_y = hit_point.y - global_position.y
		
	var multiplier: float = MULT_CHEST
	var hit_part_name: String = "PEITO"
	var number_color: Color = Color(1.0, 0.9, 0.9)
	
	if relative_y >= 1.52:
		multiplier = MULT_HEAD
		hit_part_name = "HEADSHOT!"
		number_color = Color(1.0, 0.2, 0.2) # Vermelho vivo no headshot
	elif relative_y < 0.57:
		multiplier = MULT_LEGS
		hit_part_name = "PERNAS"
		number_color = Color(0.8, 0.8, 0.8) # Cinza claro nas pernas
		
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
		_die(attacker_name, attacker_team)

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
	
	# Sobe e desaparece suavemente
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
func _die(killer_name: String, killer_team: String) -> void:
	current_state = State.DEAD
	died.emit(killer_name, killer_team, bot_name, team)
	
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
	
	collision_shape.set_deferred("disabled", false)
	_pick_new_patrol_destination()
