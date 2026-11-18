extends StaticBody3D

## Sinais emitidos pelo alvo
signal destroyed(score_value: int, target_node: Node3D)
signal damaged(remaining_hp: int)

## Configurações do Alvo
@export var max_health: int = 30
@export var score_value: int = 100
@export var respawn_time: float = 2.0
@export var auto_rotate: bool = true
@export var rotation_speed: float = 1.5

## Limites para respawn aleatório dentro da arena
@export var arena_bounds_min: Vector3 = Vector3(-16.0, 1.2, -16.0)
@export var arena_bounds_max: Vector3 = Vector3(16.0, 3.0, 16.0)

var current_health: int = 30
var is_active: bool = true
var base_color: Color = Color(0.9, 0.2, 0.2)
var hit_color: Color = Color(1.0, 1.0, 1.0)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var respawn_timer: Timer = $RespawnTimer

var target_material: StandardMaterial3D
var hit_tween: Tween

func _ready() -> void:
	current_health = max_health
	
	# Garante material exclusivo para este alvo (para piscar independentemente)
	target_material = StandardMaterial3D.new()
	target_material.albedo_color = base_color
	target_material.roughness = 0.3
	target_material.metallic = 0.1
	target_material.emission_enabled = true
	target_material.emission = Color(0.3, 0.05, 0.05)
	mesh_instance.material_override = target_material
	
	respawn_timer.timeout.connect(_on_respawn_timer_timeout)

func _process(delta: float) -> void:
	if is_active and auto_rotate:
		mesh_instance.rotate_y(rotation_speed * delta)

## Chamado pelo sistema de tiro hitscan do jogador
func take_damage(amount: int) -> void:
	if not is_active:
		return
		
	current_health = max(0, current_health - amount)
	damaged.emit(current_health)
	
	# Efeito visual de piscar ao receber dano
	_flash_hit()
	
	if current_health <= 0:
		_die()

## Efeito de flash e tremor ao tomar tiro
func _flash_hit() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
		
	hit_tween = create_tween()
	# Fica momentaneamente branco/brilhante
	hit_tween.tween_property(target_material, "albedo_color", hit_color, 0.04)
	hit_tween.parallel().tween_property(target_material, "emission", Color(0.8, 0.8, 0.8), 0.04)
	# Retorna à cor vermelha
	hit_tween.tween_property(target_material, "albedo_color", base_color, 0.12)
	hit_tween.parallel().tween_property(target_material, "emission", Color(0.3, 0.05, 0.05), 0.12)

## Lógica de destruição com animação e respawn
func _die() -> void:
	is_active = false
	destroyed.emit(score_value, self)
	
	# Desabilita colisão imediatamente
	collision_shape.set_deferred("disabled", true)
	
	# Animação de colapso/encolhimento
	var death_tween := create_tween()
	death_tween.tween_property(mesh_instance, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Inicia contagem para renascer
	respawn_timer.start(respawn_time)

## Renasce o alvo em uma nova posição
func _on_respawn_timer_timeout() -> void:
	# Escolhe nova posição aleatória segura dentro da arena
	var new_pos := Vector3(
		randf_range(arena_bounds_min.x, arena_bounds_max.x),
		randf_range(arena_bounds_min.y, arena_bounds_max.y),
		randf_range(arena_bounds_min.z, arena_bounds_max.z)
	)
	global_position = new_pos
	
	# Restaura estado
	current_health = max_health
	is_active = true
	target_material.albedo_color = base_color
	target_material.emission = Color(0.3, 0.05, 0.05)
	
	# Animação de surgimento com pop elástico
	mesh_instance.scale = Vector3.ZERO
	var spawn_tween := create_tween()
	spawn_tween.tween_property(mesh_instance, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	collision_shape.set_deferred("disabled", false)
