extends CharacterBody3D

## Sinais de estado do jogador
signal health_changed(current_hp: int, max_hp: int)
signal died(killer_name: String, killer_team: String, victim_name: String, victim_team: String, is_headshot: bool)
signal damage_dealt_to_self(amount: int, attacker_name: String, attacker_team: String)

## Sinais de Armas, Dinheiro e Mercado
signal money_changed(new_money: int)
signal ammo_changed(current_clip: int, reserve_ammo: int, weapon_name: String)
signal grenades_changed(count: int)
signal buy_zone_status_changed(in_buy_zone: bool)
signal enemy_base_infiltrated(bonus_amount: int)
signal aim_changed(is_aiming: bool)

## Configurações de Time e Identificação
@export var team: String = "blue"
@export var character_name: String = "Você"
@export var max_health: int = 100
@export var money: int = 1200 # Dinheiro inicial do jogador

## Configurações de Multiplayer
var peer_id: int = 1
var is_remote: bool = false
var sync_target_pos: Vector3 = Vector3.ZERO
var sync_target_rot_y: float = 0.0
var sync_target_head_x: float = 0.0
var sync_timer: float = 0.0

## Controles Touch (Mobile)
var touch_move_vector: Vector2 = Vector2.ZERO
var touch_shoot_held: bool = false
var touch_just_shot: bool = false
var touch_aim_active: bool = false

var match_active: bool = false
var can_claim_enemy_base_reward: bool = true
var in_enemy_base: bool = false

## Configurações de Movimento
@export_group("Movimentação")
@export var walk_speed: float = 6.5
@export var sprint_speed: float = 10.0
@export var jump_velocity: float = 5.0
@export var acceleration: float = 12.0
@export var deceleration: float = 14.0
@export var air_control: float = 4.0

## Configurações de Câmera
@export_group("Câmera")
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -85.0
@export var max_pitch: float = 85.0

const MULT_HEAD: float = 2.2
const MULT_CHEST: float = 1.0
const MULT_LEGS: float = 0.7

var current_health: int = 100
var is_dead: bool = false
var spawn_position: Vector3 = Vector3(0, 1.0, 64.0)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Estado de compra e base
var is_in_buy_zone: bool = true

# Sistema de Mira (ADS)
var is_aiming: bool = false
var default_fov: float = 75.0
var aim_fov: float = 50.0
var default_weapon_pos: Vector3 = Vector3(0.28, -0.22, -0.45)
var ads_weapon_pos: Vector3 = Vector3(0.0, -0.155, -0.38)
var current_weapon_base_pos: Vector3 = Vector3(0.28, -0.22, -0.45)

# Sistema de Armas e Munição
var grenades_count: int = 1
var max_grenades: int = 3
var is_reloading: bool = false

var weapons_db: Dictionary = {
	"pistol": {
		"name": "Pistola Padrão",
		"damage": 25,
		"fire_rate": 0.20,
		"clip_size": 12,
		"current_clip": 12,
		"reserve_ammo": 48,
		"max_reserve": 48,
		"auto_fire": false,
		"mesh_size": Vector3(0.08, 0.1, 0.4),
		"mesh_color": Color(0.2, 0.22, 0.25)
	},
	"magnum": {
		"name": "Pistola Magnum .50",
		"damage": 50,
		"fire_rate": 0.38,
		"clip_size": 7,
		"current_clip": 7,
		"reserve_ammo": 28,
		"max_reserve": 28,
		"auto_fire": false,
		"mesh_size": Vector3(0.09, 0.13, 0.46),
		"mesh_color": Color(0.4, 0.38, 0.35)
	},
	"smg": {
		"name": "Submetralhadora SMG",
		"damage": 18,
		"fire_rate": 0.09,
		"clip_size": 30,
		"current_clip": 30,
		"reserve_ammo": 120,
		"max_reserve": 120,
		"auto_fire": true,
		"mesh_size": Vector3(0.09, 0.12, 0.52),
		"mesh_color": Color(0.18, 0.25, 0.3)
	},
	"rifle": {
		"name": "Rifle de Assalto M4",
		"damage": 32,
		"fire_rate": 0.13,
		"clip_size": 30,
		"current_clip": 30,
		"reserve_ammo": 90,
		"max_reserve": 90,
		"auto_fire": true,
		"mesh_size": Vector3(0.09, 0.14, 0.65),
		"mesh_color": Color(0.25, 0.28, 0.22)
	},
	"lmg": {
		"name": "Metralhadora Pesada LMG",
		"damage": 36,
		"fire_rate": 0.11,
		"clip_size": 60,
		"current_clip": 60,
		"reserve_ammo": 180,
		"max_reserve": 180,
		"auto_fire": true,
		"mesh_size": Vector3(0.11, 0.16, 0.72),
		"mesh_color": Color(0.15, 0.15, 0.18)
	}
}

var owned_weapons: Array[String] = ["rifle", "pistol"]
var current_weapon_id: String = "rifle"

var can_shoot: bool = true
var default_weapon_rot: Vector3
var weapon_recoil_tween: Tween
var head_bob_time: float = 0.0
var step_cycle: float = 0.0

# Cena da granada pré-carregada
var grenade_scene: PackedScene = preload("res://scenes/grenade.tscn")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var gun_mesh: MeshInstance3D = $Head/Camera3D/WeaponHolder/GunMesh
@onready var muzzle: Marker3D = $Head/Camera3D/WeaponHolder/Muzzle
@onready var shoot_timer: Timer = $ShootTimer
@onready var respawn_timer: Timer = $RespawnTimer

func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	sync_target_pos = global_position
	
	collision_layer = 2
	collision_mask = 3
	
	InputSetup.ensure_inputs()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	default_weapon_pos = weapon_holder.position
	default_weapon_rot = weapon_holder.rotation
	current_weapon_base_pos = default_weapon_pos
	
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(func(): can_shoot = true)
	
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn)
	
	raycast.target_position = Vector3(0, 0, -140.0)
	raycast.collision_mask = 3
	raycast.collide_with_bodies = true
	raycast.collide_with_areas = true
	
	# Inicializa interface de armas e dinheiro
	_equip_weapon("rifle")
	money_changed.emit(money)
	grenades_changed.emit(grenades_count)
	buy_zone_status_changed.emit(is_in_buy_zone)

## Configura o jogador para rede (autoridade, time e visibilidade de modelo 3D)
func setup_multiplayer(id: int, p_name: String, p_team: String, remote: bool) -> void:
	peer_id = id
	is_remote = remote
	character_name = p_name
	team = p_team
	set_multiplayer_authority(id)
	
	var body_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if is_remote:
		if camera:
			camera.current = false
		if body_mesh:
			body_mesh.visible = true
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.45, 0.95) if team == "blue" else Color(0.95, 0.25, 0.25)
			mat.roughness = 0.5
			body_mesh.material_override = mat
	else:
		if camera:
			camera.current = true
		if body_mesh:
			body_mesh.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if is_remote:
		return
	if not match_active or is_dead:
		return
		
	# Rotação do mouse (com sensibilidade ajustada para mira ADS)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var current_sens: float = mouse_sensitivity * (0.55 if is_aiming else 1.0)
		rotate_y(-event.relative.x * current_sens)
		head.rotate_x(-event.relative.y * current_sens)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	# Recarga manual com R
	if event.is_action_pressed("reload"):
		_reload()
		
	# Lançamento de granada com F (não lança se estiver no mercado)
	if event.is_action_pressed("throw_grenade"):
		if not Input.is_action_pressed("buy_menu"):
			_throw_grenade()
		
	# Troca de armas com o Scroll do Mouse ou atalhos de números (se não estiver no mercado)
	if not Input.is_action_pressed("buy_menu"):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_weapon(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cycle_weapon(-1)
		elif event.is_action_pressed("next_weapon"):
			_cycle_weapon(1)
		elif event.is_action_pressed("prev_weapon"):
			_cycle_weapon(-1)
		else:
			for i in range(min(5, owned_weapons.size())):
				if event.is_action_pressed("slot_%d" % (i + 1)):
					_equip_weapon(owned_weapons[i])
	
	# Alternar cursor com ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	# Recaptura o mouse ao clicar na cena 3D (apenas se NÃO estiver segurando CTRL ou TAB)
	if event is InputEventMouseButton and event.pressed:
		if not Input.is_action_pressed("buy_menu") and not Input.is_action_pressed("scoreboard"):
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not match_active or is_dead:
		return
		
	if is_remote:
		global_position = global_position.lerp(sync_target_pos, 16.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_target_rot_y, 16.0 * delta)
		if head:
			head.rotation.x = lerp_angle(head.rotation.x, sync_target_head_x, 16.0 * delta)
		return
		
	_handle_gravity(delta)
	_handle_jump()
	_handle_aim(delta)
	_handle_movement(delta)
	_handle_weapon_bobbing(delta)
	_handle_shooting()
	
	move_and_slide()
	
	# Sincroniza posição e rotação pela rede quando conectado
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		sync_timer += delta
		if sync_timer >= 0.033:
			sync_timer = 0.0
			rpc("rpc_sync_transform", global_position, rotation.y, head.rotation.x)
	
	# 1. Base Aliada (Azul - Z > 44.0): Compras permitidas e vida recuperada para 100%
	var in_zone: bool = (global_position.z > 44.0)
	if in_zone != is_in_buy_zone:
		is_in_buy_zone = in_zone
		buy_zone_status_changed.emit(is_in_buy_zone)
		
	if is_in_buy_zone and current_health < max_health and not is_dead:
		current_health = max_health
		health_changed.emit(current_health, max_health)
		AudioManager.play("heal", -1.0, 1.0)
		
	# 2. Base Inimiga (Vermelha - Z < -44.0): Bônus de Invasão de +$2,000!
	var at_enemy_base: bool = (global_position.z < -44.0)
	if at_enemy_base and not in_enemy_base:
		in_enemy_base = true
		if can_claim_enemy_base_reward:
			can_claim_enemy_base_reward = false
			add_money(2000)
			AudioManager.play("buy", 2.0, 1.0)
			enemy_base_infiltrated.emit(2000)
	elif not at_enemy_base and global_position.z > -36.0:
		in_enemy_base = false
		can_claim_enemy_base_reward = true

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

## Controla o Aim Down Sights (Mira com Botão Direito do Mouse ou Botão Touch)
func _handle_aim(delta: float) -> void:
	var wants_aim: bool = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Input.is_action_pressed("buy_menu") and not Input.is_action_pressed("scoreboard"):
		wants_aim = Input.is_action_pressed("aim") or touch_aim_active
	elif touch_aim_active:
		wants_aim = true
		
	if wants_aim != is_aiming:
		is_aiming = wants_aim
		aim_changed.emit(is_aiming)
		
	var target_fov: float = aim_fov if is_aiming else default_fov
	camera.fov = lerp(camera.fov, target_fov, 14.0 * delta)
	
	var target_pos: Vector3 = ads_weapon_pos if is_aiming else default_weapon_pos
	current_weapon_base_pos = current_weapon_base_pos.lerp(target_pos, 14.0 * delta)

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move_vector != Vector2.ZERO:
		input_dir = touch_move_vector
		
	var move_direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# No touch, se puxar o analógico para frente mais de 75%, ativa sprint automático
	var is_sprinting := (Input.is_action_pressed("sprint") or (touch_move_vector.y < -0.75)) and not is_aiming
	var target_speed := sprint_speed if (is_sprinting and input_dir.y < 0) else (walk_speed * 0.72 if is_aiming else walk_speed)
	
	var accel_factor := acceleration if is_on_floor() else air_control
	var decel_factor := deceleration if is_on_floor() else air_control
	
	if move_direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, move_direction.x * target_speed, accel_factor * delta)
		velocity.z = lerp(velocity.z, move_direction.z * target_speed, accel_factor * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, decel_factor * delta)
		velocity.z = lerp(velocity.z, 0.0, decel_factor * delta)

func _handle_weapon_bobbing(delta: float) -> void:
	if weapon_recoil_tween and weapon_recoil_tween.is_running():
		return
	if is_reloading:
		return
		
	var horizontal_vel := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_vel > 0.5:
		var bob_factor: float = 0.2 if is_aiming else 1.0
		head_bob_time += delta * horizontal_vel * 1.8
		weapon_holder.position.y = current_weapon_base_pos.y + sin(head_bob_time) * 0.015 * bob_factor
		weapon_holder.position.x = current_weapon_base_pos.x + cos(head_bob_time * 0.5) * 0.01 * bob_factor
		weapon_holder.position.z = current_weapon_base_pos.z
		
		# Som sutil de passos ao caminhar/correr
		step_cycle += delta * horizontal_vel
		if step_cycle > 2.8:
			step_cycle = 0.0
			AudioManager.play("footstep", -12.0, randf_range(0.92, 1.08))
			if horizontal_vel > 7.0:
				_alert_nearby_bots(global_position, 0.45)
	else:
		head_bob_time = 0.0
		step_cycle = 0.0
		weapon_holder.position = weapon_holder.position.lerp(current_weapon_base_pos, 12.0 * delta)

## Gerencia o disparo (automático ou semi-automático)
func _handle_shooting() -> void:
	if is_reloading:
		return
		
	# Se o menu de compras (CTRL) ou placar (TAB) estiver aberto, NÃO atira
	if Input.is_action_pressed("buy_menu") or Input.is_action_pressed("scoreboard"):
		return
		
	# No PC sem touch, o mouse precisa estar capturado para atirar
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not touch_shoot_held and not touch_just_shot:
		return
		
	var w = weapons_db[current_weapon_id]
	var shoot_pressed: bool = (Input.is_action_pressed("shoot") or touch_shoot_held) if w["auto_fire"] else (Input.is_action_just_pressed("shoot") or touch_just_shot)
	touch_just_shot = false
	
	if shoot_pressed and can_shoot:
		_try_shoot()

## Métodos para interface de toque (Mobile Touchscreen)
func apply_touch_look(delta_vec: Vector2) -> void:
	if not match_active or is_dead or is_remote:
		return
	var current_sens: float = mouse_sensitivity * (0.55 if is_aiming else 1.0) * 1.5
	rotate_y(-delta_vec.x * current_sens)
	head.rotate_x(-delta_vec.y * current_sens)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func trigger_touch_jump() -> void:
	if is_on_floor() and not is_dead and match_active and not is_remote:
		velocity.y = jump_velocity

func toggle_touch_aim() -> void:
	touch_aim_active = not touch_aim_active

func _try_shoot() -> void:
	var w = weapons_db[current_weapon_id]
	
	# Verifica se há balas no pente
	if w["current_clip"] > 0:
		w["current_clip"] -= 1
		_shoot_projectile(w)
		ammo_changed.emit(w["current_clip"], w["reserve_ammo"], w["name"])
	else:
		# Se o pente está vazio, tenta recarregar ou avisa falta de munição
		if w["reserve_ammo"] > 0:
			_reload()
		else:
			# Pente e reserva vazios!
			_dry_fire_effect()

## Disparo hitscan da arma
func _shoot_projectile(w: Dictionary) -> void:
	can_shoot = false
	shoot_timer.start(w["fire_rate"])
	
	# Som do tiro específico para cada arma
	match current_weapon_id:
		"magnum":
			AudioManager.play("shoot_magnum", 1.5, randf_range(0.96, 1.04))
		"smg":
			AudioManager.play("shoot_smg", -1.0, randf_range(0.96, 1.04))
		"rifle":
			AudioManager.play("shoot_rifle", 0.0, randf_range(0.96, 1.04))
		"lmg":
			AudioManager.play("shoot_rifle", 1.2, randf_range(0.88, 0.94))
		_:
			AudioManager.play("shoot_pistol", 0.0, randf_range(0.96, 1.04))
	
	_alert_nearby_bots(muzzle.global_position, 1.0)
	_apply_recoil()
	raycast.force_raycast_update()
	
	var from_pos: Vector3 = muzzle.global_position
	var to_pos: Vector3
	
	if raycast.is_colliding():
		to_pos = raycast.get_collision_point()
		var collider = raycast.get_collider()
		
		if collider and collider.has_method("take_damage"):
			collider.take_damage(w["damage"], character_name, team, to_pos)
			# Ganha recompensa em dinheiro por acerto
			add_money(15)
			
			# Som de impacto ou headshot
			var is_head: bool = false
			if collider is Node3D:
				var hit_local_y: float = to_pos.y - collider.global_position.y
				if hit_local_y > 1.52:
					is_head = true
			if is_head:
				AudioManager.play("headshot", 2.0, 1.0)
			else:
				AudioManager.play("hit", 1.0, randf_range(0.98, 1.02))
			
		_spawn_hit_spark(to_pos, raycast.get_collision_normal())
	else:
		to_pos = raycast.global_transform * raycast.target_position
		
	_spawn_tracer_line(from_pos, to_pos)
	
	# Transmite efeito visual e sonoro do disparo aos outros peers
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc("rpc_shoot_effect", from_pos, to_pos, current_weapon_id)

## Clique seco ao tentar atirar sem munição
func _dry_fire_effect() -> void:
	AudioManager.play("empty_click", 2.0, 1.0)
	can_shoot = false
	shoot_timer.start(0.25)
	var tween := create_tween()
	tween.tween_property(weapon_holder, "position:z", default_weapon_pos.z + 0.02, 0.04)
	tween.tween_property(weapon_holder, "position:z", default_weapon_pos.z, 0.06)

## Lógica de recarga da arma atual
func _reload() -> void:
	var w = weapons_db[current_weapon_id]
	if is_reloading or w["current_clip"] == w["clip_size"] or w["reserve_ammo"] <= 0:
		return
		
	is_reloading = true
	can_shoot = false
	AudioManager.play("reload", 0.0, 1.0)
	
	# Animação de baixar e subir a arma para recarga
	var reload_tween := create_tween()
	reload_tween.tween_property(weapon_holder, "position:y", default_weapon_pos.y - 0.25, 0.35)
	reload_tween.tween_interval(0.4)
	reload_tween.tween_property(weapon_holder, "position:y", default_weapon_pos.y, 0.35)
	
	reload_tween.tween_callback(func():
		var needed: int = w["clip_size"] - w["current_clip"]
		var amount_to_load: int = min(needed, w["reserve_ammo"])
		w["current_clip"] += amount_to_load
		w["reserve_ammo"] -= amount_to_load
		is_reloading = false
		can_shoot = true
		ammo_changed.emit(w["current_clip"], w["reserve_ammo"], w["name"])
	)

## Lança uma granada fragmentária
func _throw_grenade() -> void:
	if grenades_count <= 0 or is_reloading:
		return
		
	grenades_count -= 1
	grenades_changed.emit(grenades_count)
	AudioManager.play("grenade_throw", 0.0, 1.0)
	
	var nade = grenade_scene.instantiate() as RigidBody3D
	nade.thrower_name = character_name
	nade.thrower_team = team
	nade.global_position = camera.global_position + (-camera.global_transform.basis.z * 0.8)
	
	# Aplica força de arremesso
	var throw_dir: Vector3 = (-camera.global_transform.basis.z * 18.0) + Vector3(0, 3.5, 0)
	nade.linear_velocity = throw_dir
	nade.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	
	get_tree().root.add_child(nade)
	
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc("rpc_throw_grenade_network", nade.global_position, throw_dir, character_name, team)

## Troca a arma atual equipada
func _equip_weapon(weapon_id: String) -> void:
	if not weapons_db.has(weapon_id):
		return
		
	current_weapon_id = weapon_id
	var w = weapons_db[weapon_id]
	is_reloading = false
	can_shoot = true
	
	# Ajusta modelo 3D da arma
	if gun_mesh:
		var box_mesh := BoxMesh.new()
		box_mesh.size = w["mesh_size"]
		gun_mesh.mesh = box_mesh
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = w["mesh_color"]
		mat.metallic = 0.7
		mat.roughness = 0.35
		gun_mesh.material_override = mat
		
	ammo_changed.emit(w["current_clip"], w["reserve_ammo"], w["name"])

## Alterna ciclicamente entre as armas possuídas pelo jogador via Scroll do Mouse
func _cycle_weapon(direction: int) -> void:
	if owned_weapons.size() <= 1:
		return
	var idx: int = owned_weapons.find(current_weapon_id)
	if idx == -1:
		idx = 0
	var next_idx: int = (idx + direction) % owned_weapons.size()
	if next_idx < 0:
		next_idx += owned_weapons.size()
	_equip_weapon(owned_weapons[next_idx])
	AudioManager.play("reload", -6.0, 1.4)

## Verifica se todas as armas do jogador já estão 100% carregadas (pente e reserva)
func is_ammo_full() -> bool:
	for w_id in owned_weapons:
		var w = weapons_db[w_id]
		if w["reserve_ammo"] < w["max_reserve"] or w["current_clip"] < w["clip_size"]:
			return false
	return true

## Sistema de Compra no Mercado da Base
func buy_item(item_id: String) -> Dictionary:
	# 1. Verifica se o jogador está na Base Azul
	if not is_in_buy_zone:
		AudioManager.play("buy_error", -2.0, 1.0)
		return {"success": false, "message": "🚫 COMPRA PROIBIDA: Compras são permitidas apenas na SUA BASE (Base Azul)!"}
		
	var prices = {
		"magnum": 500,
		"smg": 1200,
		"rifle": 2000,
		"lmg": 3000,
		"grenade": 300,
		"ammo": 200
	}
	
	if not prices.has(item_id):
		AudioManager.play("buy_error", -2.0, 1.0)
		return {"success": false, "message": "Item inválido!"}
		
	# Bloqueio prévio de recompra de munição se já estiver 100% cheio
	if item_id == "ammo" and is_ammo_full():
		AudioManager.play("buy_error", -2.0, 1.0)
		return {"success": false, "message": "🚫 MUNIÇÃO 100% CHEIA! Não é necessário comprar mais munição."}
		
	# Se for arma que o jogador já possui, apenas equipa sem cobrar novamente
	if item_id != "ammo" and item_id != "grenade" and owned_weapons.has(item_id):
		_equip_weapon(item_id)
		AudioManager.play("buy", -2.0, 1.1)
		return {"success": true, "message": "Você já possui %s! Arma equipada." % weapons_db[item_id]["name"]}
		
	var price: int = prices[item_id]
	if money < price:
		AudioManager.play("buy_error", -2.0, 1.0)
		return {"success": false, "message": "Dinheiro insuficiente! (Custa $%d)" % price}
		
	# Processa a compra
	match item_id:
		"grenade":
			if grenades_count >= max_grenades:
				AudioManager.play("buy_error", -2.0, 1.0)
				return {"success": false, "message": "🚫 Limite de granadas atingido (%d/%d)!" % [grenades_count, max_grenades]}
			money -= price
			grenades_count += 1
			grenades_changed.emit(grenades_count)
			money_changed.emit(money)
			AudioManager.play("buy", 0.0, 1.0)
			return {"success": true, "message": "Granada comprada com sucesso!"}
			
		"ammo":
			if is_ammo_full():
				AudioManager.play("buy_error", -2.0, 1.0)
				return {"success": false, "message": "🚫 MUNIÇÃO 100% CHEIA! Não é necessário comprar mais munição."}
			money -= price
			# Reabastece todas as armas que o jogador possui ao máximo (reserva e pente)
			for w_id in owned_weapons:
				var w = weapons_db[w_id]
				w["current_clip"] = w["clip_size"]
				w["reserve_ammo"] = w["max_reserve"]
			var current_w = weapons_db[current_weapon_id]
			ammo_changed.emit(current_w["current_clip"], current_w["reserve_ammo"], current_w["name"])
			money_changed.emit(money)
			AudioManager.play("buy", 0.0, 1.0)
			return {"success": true, "message": "✅ Munições 100% reabastecidas com sucesso!"}
			
		_:
			# Compra de nova arma
			money -= price
			if not owned_weapons.has(item_id):
				owned_weapons.append(item_id)
			# Reabastece munição completa da arma comprada
			weapons_db[item_id]["current_clip"] = weapons_db[item_id]["clip_size"]
			weapons_db[item_id]["reserve_ammo"] = weapons_db[item_id]["max_reserve"]
			_equip_weapon(item_id)
			money_changed.emit(money)
			AudioManager.play("buy", 0.0, 1.0)
			return {"success": true, "message": "%s comprada e equipada!" % weapons_db[item_id]["name"]}

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func _apply_recoil() -> void:
	if weapon_recoil_tween and weapon_recoil_tween.is_valid():
		weapon_recoil_tween.kill()
		
	var base_pos: Vector3 = ads_weapon_pos if is_aiming else default_weapon_pos
	var base_rot: Vector3 = default_weapon_rot
	var kick_z: float = 0.04 if is_aiming else 0.08
	var kick_y: float = 0.01 if is_aiming else 0.02
	var kick_rot: float = 2.0 if is_aiming else 4.0
	
	weapon_recoil_tween = create_tween()
	weapon_recoil_tween.tween_property(weapon_holder, "position:z", base_pos.z + kick_z, 0.04)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "position:y", base_pos.y + kick_y, 0.04)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "rotation:x", base_rot.x + deg_to_rad(kick_rot), 0.04)
	
	weapon_recoil_tween.tween_property(weapon_holder, "position", base_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "rotation", base_rot, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _spawn_tracer_line(start_point: Vector3, end_point: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh
	
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.88, 0.3, 0.95)
	mesh_instance.material_override = material
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start_point)
	immediate_mesh.surface_add_vertex(end_point)
	immediate_mesh.surface_end()
	
	get_tree().root.add_child(mesh_instance)
	
	var tween := mesh_instance.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.06)
	tween.tween_callback(mesh_instance.queue_free)

func _spawn_hit_spark(pos: Vector3, normal: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	spark.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	spark.material_override = mat
	
	spark.global_position = pos + normal * 0.02
	get_tree().root.add_child(spark)
	
	var tween := spark.create_tween()
	tween.tween_property(spark, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(spark.queue_free)

func _alert_nearby_bots(origin: Vector3, intensity: float) -> void:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c != self and is_instance_valid(c) and c.has_method("hear_sound"):
			c.hear_sound(origin, intensity)

func take_damage(base_amount: int, attacker_name: String = "Inimigo", attacker_team: String = "red", hit_point: Vector3 = Vector3.ZERO) -> void:
	if is_dead or attacker_team == team:
		return
		
	# Se for um nó de jogador remoto, redireciona o dano via RPC para a máquina do jogador dono
	if is_remote and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc_id(peer_id, "rpc_receive_damage", base_amount, attacker_name, attacker_team, hit_point)
		return
		
	var relative_y: float = 1.0
	if hit_point != Vector3.ZERO:
		relative_y = hit_point.y - global_position.y
		
	var multiplier: float = MULT_CHEST
	var is_headshot: bool = false
	if relative_y >= 1.52:
		multiplier = MULT_HEAD
		is_headshot = true
	elif relative_y < 0.57:
		multiplier = MULT_LEGS
		
	var final_damage: int = int(round(base_amount * multiplier))
	current_health = max(0, current_health - final_damage)
	damage_dealt_to_self.emit(final_damage, attacker_name, attacker_team)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_die(attacker_name, attacker_team, is_headshot)

func _die(killer_name: String, killer_team: String, is_headshot: bool = false) -> void:
	is_dead = true
	died.emit(killer_name, killer_team, character_name, team, is_headshot)
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)
	
	# Se estiver em rede, avisa os outros clientes sobre o abate
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc("rpc_notify_death", killer_name, killer_team, is_headshot)
		
	respawn_timer.start(2.8)

func _respawn() -> void:
	current_health = max_health
	is_dead = false
	can_claim_enemy_base_reward = true
	in_enemy_base = false
	global_position = spawn_position + Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(-2.0, 2.0))
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", false)
	health_changed.emit(current_health, max_health)

## RPCs de Sincronização Multiplayer
@rpc("unreliable")
func rpc_sync_transform(pos: Vector3, rot_y: float, head_x: float) -> void:
	sync_target_pos = pos
	sync_target_rot_y = rot_y
	sync_target_head_x = head_x

@rpc("any_peer")
func rpc_receive_damage(base_amount: int, attacker_name: String, attacker_team: String, hit_point: Vector3) -> void:
	if not is_remote:
		take_damage(base_amount, attacker_name, attacker_team, hit_point)

@rpc("any_peer")
func rpc_notify_death(killer_name: String, killer_team: String, is_headshot: bool) -> void:
	if is_remote and not is_dead:
		is_dead = true
		died.emit(killer_name, killer_team, character_name, team, is_headshot)
		$CollisionShape3D.set_deferred("disabled", true)
		respawn_timer.start(2.8)

@rpc("any_peer")
func rpc_shoot_effect(from_pos: Vector3, to_pos: Vector3, weapon_id: String) -> void:
	_spawn_tracer_line(from_pos, to_pos)
	match weapon_id:
		"magnum":
			AudioManager.play("shoot_magnum", 0.0, 1.0)
		"smg":
			AudioManager.play("shoot_smg", -2.0, 1.0)
		"rifle", "lmg":
			AudioManager.play("shoot_rifle", 0.0, 1.0)
		_:
			AudioManager.play("shoot_pistol", 0.0, 1.0)

@rpc("any_peer")
func rpc_throw_grenade_network(spawn_pos: Vector3, velocity_vec: Vector3, thrower: String, t_team: String) -> void:
	var nade = grenade_scene.instantiate() as RigidBody3D
	nade.thrower_name = thrower
	nade.thrower_team = t_team
	nade.global_position = spawn_pos
	nade.linear_velocity = velocity_vec
	nade.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	get_tree().root.add_child(nade)
