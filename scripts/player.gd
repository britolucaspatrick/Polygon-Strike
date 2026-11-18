extends CharacterBody3D

## Sinais de estado do jogador
signal health_changed(current_hp: int, max_hp: int)
signal died(killer_name: String, killer_team: String, victim_name: String, victim_team: String)
signal damage_dealt_to_self(amount: int, attacker_name: String, attacker_team: String)

## Sinais de Armas, Dinheiro e Mercado
signal money_changed(new_money: int)
signal ammo_changed(current_clip: int, reserve_ammo: int, weapon_name: String)
signal grenades_changed(count: int)
signal buy_zone_status_changed(in_buy_zone: bool)
signal enemy_base_infiltrated(bonus_amount: int)

## Configurações de Time e Identificação
@export var team: String = "blue"
@export var character_name: String = "Você"
@export var max_health: int = 100
@export var money: int = 1200 # Dinheiro inicial do jogador

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

var owned_weapons: Array[String] = ["pistol"]
var current_weapon_id: String = "pistol"

var can_shoot: bool = true
var default_weapon_pos: Vector3
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
	
	collision_layer = 2
	collision_mask = 3
	
	InputSetup.ensure_inputs()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	default_weapon_pos = weapon_holder.position
	default_weapon_rot = weapon_holder.rotation
	
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(func(): can_shoot = true)
	
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn)
	
	raycast.target_position = Vector3(0, 0, -140.0)
	raycast.collision_mask = 3
	raycast.collide_with_bodies = true
	raycast.collide_with_areas = true
	
	# Inicializa interface de armas e dinheiro
	_equip_weapon("pistol")
	money_changed.emit(money)
	grenades_changed.emit(grenades_count)
	buy_zone_status_changed.emit(is_in_buy_zone)

func _unhandled_input(event: InputEvent) -> void:
	if not match_active or is_dead:
		return
		
	# Rotação do mouse
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	# Recarga manual com R
	if event.is_action_pressed("reload"):
		_reload()
		
	# Lançamento de granada com F (não lança se estiver no mercado)
	if event.is_action_pressed("throw_grenade"):
		if not Input.is_action_pressed("buy_menu"):
			_throw_grenade()
		
	# Troca de armas com números 1, 2, 3 (se não estiver no mercado)
	if not Input.is_action_pressed("buy_menu"):
		if event.is_action_pressed("slot_1") and owned_weapons.size() > 0:
			_equip_weapon(owned_weapons[0])
		elif event.is_action_pressed("slot_2") and owned_weapons.size() > 1:
			_equip_weapon(owned_weapons[1])
		elif event.is_action_pressed("slot_3") and owned_weapons.size() > 2:
			_equip_weapon(owned_weapons[2])
	
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
		
	_handle_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	_handle_weapon_bobbing(delta)
	_handle_shooting()
	
	move_and_slide()
	
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

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting := Input.is_action_pressed("sprint")
	var target_speed := sprint_speed if (is_sprinting and input_dir.y < 0) else walk_speed
	
	var accel_factor := acceleration if is_on_floor() else air_control
	var decel_factor := deceleration if is_on_floor() else air_control
	
	if move_direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, move_direction.x * target_speed, accel_factor * delta)
		velocity.z = lerp(velocity.z, move_direction.z * target_speed, accel_factor * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, decel_factor * delta)
		velocity.z = lerp(velocity.z, 0.0, decel_factor * delta)

func _handle_weapon_bobbing(delta: float) -> void:
	var horizontal_vel := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_vel > 0.5:
		head_bob_time += delta * horizontal_vel * 1.8
		weapon_holder.position.y = default_weapon_pos.y + sin(head_bob_time) * 0.015
		weapon_holder.position.x = default_weapon_pos.x + cos(head_bob_time * 0.5) * 0.01
		
		# Som sutil de passos ao caminhar/correr
		step_cycle += delta * horizontal_vel
		if step_cycle > 2.8:
			step_cycle = 0.0
			AudioManager.play("footstep", -12.0, randf_range(0.92, 1.08))
	else:
		head_bob_time = 0.0
		step_cycle = 0.0
		weapon_holder.position = weapon_holder.position.lerp(default_weapon_pos, 8.0 * delta)

## Gerencia o disparo (automático ou semi-automático)
func _handle_shooting() -> void:
	if is_reloading:
		return
		
	# Se o menu de compras (CTRL) ou placar (TAB) estiver aberto,
	# ou se o cursor do mouse estiver livre, NÃO atira de forma alguma.
	# O clique esquerdo fica 100% exclusivo para clicar nos botões do mercado.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Input.is_action_pressed("buy_menu") or Input.is_action_pressed("scoreboard"):
		return
		
	var w = weapons_db[current_weapon_id]
	var shoot_pressed: bool = Input.is_action_pressed("shoot") if w["auto_fire"] else Input.is_action_just_pressed("shoot")
	
	if shoot_pressed and can_shoot:
		_try_shoot()

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
		
	weapon_recoil_tween = create_tween()
	weapon_recoil_tween.tween_property(weapon_holder, "position:z", default_weapon_pos.z + 0.08, 0.04)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "position:y", default_weapon_pos.y + 0.02, 0.04)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "rotation:x", default_weapon_rot.x + deg_to_rad(4.0), 0.04)
	
	weapon_recoil_tween.tween_property(weapon_holder, "position", default_weapon_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	weapon_recoil_tween.parallel().tween_property(weapon_holder, "rotation", default_weapon_rot, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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

func take_damage(base_amount: int, attacker_name: String = "Inimigo", attacker_team: String = "red", hit_point: Vector3 = Vector3.ZERO) -> void:
	if is_dead or attacker_team == team:
		return
		
	var relative_y: float = 1.0
	if hit_point != Vector3.ZERO:
		relative_y = hit_point.y - global_position.y
		
	var multiplier: float = MULT_CHEST
	if relative_y >= 1.52:
		multiplier = MULT_HEAD
	elif relative_y < 0.57:
		multiplier = MULT_LEGS
		
	var final_damage: int = int(round(base_amount * multiplier))
	current_health = max(0, current_health - final_damage)
	damage_dealt_to_self.emit(final_damage, attacker_name, attacker_team)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_die(attacker_name, attacker_team)

func _die(killer_name: String, killer_team: String) -> void:
	is_dead = true
	died.emit(killer_name, killer_team, character_name, team)
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)
	
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
