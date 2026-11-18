extends RigidBody3D

## Configurações da Granada
@export var fuse_time: float = 1.8
@export var explosion_damage: int = 130
@export var explosion_radius: float = 8.5

var thrower_name: String = "Você"
var thrower_team: String = "blue"

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = fuse_time
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_explode)
	add_child(timer)

## Lógica de detonação em área
func _explode() -> void:
	var explode_pos := global_position
	
	# Som 3D de explosão com impacto estrondoso
	AudioManager.play_spatial("explosion", explode_pos, 5.0, randf_range(0.95, 1.05), 140.0)
	
	# Efeito visual de explosão com esfera de choque e luz
	_spawn_explosion_visual(explode_pos)
	
	# Aplica dano a combatentes dentro do raio
	var combatants = get_tree().get_nodes_in_group("combatants")
	for c in combatants:
		if not is_instance_valid(c):
			continue
		var dist := explode_pos.distance_to(c.global_position)
		if dist <= explosion_radius:
			var c_team = c.get("team")
			if c_team != thrower_team:
				# Dano com queda pela distância (falloff)
				var damage_factor: float = clamp(1.0 - (dist / explosion_radius), 0.25, 1.0)
				var final_damage: int = int(round(explosion_damage * damage_factor))
				if c.has_method("take_damage"):
					c.take_damage(final_damage, thrower_name, thrower_team, c.global_position + Vector3(0, 1.0, 0))
					
	queue_free()

## Cria efeitos visuais da explosão (onda de choque expansiva e clarão)
func _spawn_explosion_visual(pos: Vector3) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	sphere.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.9)
	sphere.material_override = mat
	
	sphere.global_position = pos
	get_tree().root.add_child(sphere)
	
	# Clarão de luz alaranjada
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 5.0
	light.omni_range = explosion_radius
	light.global_position = pos + Vector3(0, 0.5, 0)
	get_tree().root.add_child(light)
	
	var tween := sphere.create_tween()
	tween.tween_property(sphere, "scale", Vector3.ONE * (explosion_radius * 1.4), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.25)
	
	tween.tween_callback(func():
		sphere.queue_free()
		light.queue_free()
	)
