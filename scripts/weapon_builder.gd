class_name WeaponBuilder
extends RefCounted

## =============================================================================
## WEAPON BUILDER PROCEDURAL 3D
## Constrói modelos 3D proceduralmente detalhados, realistas e específicos
## para cada arma do Polygon Strike 5v5 sem qualquer dependência de assets externos.
## =============================================================================

# Dicionário de cache de materiais para máximo desempenho
static var _materials_cache: Dictionary = {}

static func _get_mat(key: String, color: Color, metallic: float = 0.7, roughness: float = 0.35, emission_col: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	if _materials_cache.has(key):
		return _materials_cache[key]
		
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission_col
		mat.emission_energy_multiplier = emission_energy
	
	_materials_cache[key] = mat
	return mat

static func _box(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm

static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	return cm

static func _create_part(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, mat: Material = null, part_name: String = "") -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	if rot_deg != Vector3.ZERO:
		inst.rotation_degrees = rot_deg
	if mat:
		inst.material_override = mat
	if not part_name.is_empty():
		inst.name = part_name
	parent.add_child(inst)
	return inst

## =============================================================================
## POSIÇÕES TÁTICAS DE EMPUNHADURA (PADRÃO, ADS E MUZZLE)
## =============================================================================

static func get_default_pos(weapon_id: String) -> Vector3:
	match weapon_id:
		"pistol":
			return Vector3(0.24, -0.20, -0.38)
		"magnum":
			return Vector3(0.25, -0.21, -0.42)
		"smg":
			return Vector3(0.26, -0.21, -0.44)
		"rifle":
			return Vector3(0.27, -0.22, -0.46)
		"lmg":
			return Vector3(0.29, -0.24, -0.50)
		"shotgun":
			return Vector3(0.27, -0.22, -0.48)
		"sniper":
			return Vector3(0.28, -0.23, -0.52)
		_:
			return Vector3(0.28, -0.22, -0.45)

static func get_ads_pos(weapon_id: String) -> Vector3:
	match weapon_id:
		"pistol":
			return Vector3(0.0, -0.158, -0.32)
		"magnum":
			return Vector3(0.0, -0.165, -0.35)
		"smg":
			return Vector3(0.0, -0.160, -0.36)
		"rifle":
			return Vector3(0.0, -0.170, -0.38) # Alinha o Red Dot holográfico central
		"lmg":
			return Vector3(0.0, -0.180, -0.42)
		"shotgun":
			return Vector3(0.0, -0.165, -0.40)
		"sniper":
			return Vector3(0.0, -0.175, -0.44)
		_:
			return Vector3(0.0, -0.155, -0.38)

static func get_muzzle_pos(weapon_id: String) -> Vector3:
	match weapon_id:
		"pistol":
			return Vector3(0.0, 0.024, -0.19)
		"magnum":
			return Vector3(0.0, 0.028, -0.26)
		"smg":
			return Vector3(0.0, 0.020, -0.37)
		"rifle":
			return Vector3(0.0, 0.020, -0.58)
		"lmg":
			return Vector3(0.0, 0.020, -0.65)
		"shotgun":
			return Vector3(0.0, 0.022, -0.54)
		"sniper":
			return Vector3(0.0, 0.025, -0.72)
		_:
			return Vector3(0.0, 0.02, -0.45)

## Aplica o modelo da arma no WeaponHolder (substituindo GunMesh antigo e atualizando Muzzle)
static func apply_to_weapon_holder(holder: Node3D, weapon_id: String) -> void:
	if not holder:
		return
		
	# Remove modelo procedural anterior se houver
	var old_model = holder.get_node_or_null("ProceduralWeaponModel")
	if old_model:
		old_model.queue_free()
		
	# Oculta GunMesh primitivo original de cena
	var original_gun_mesh = holder.get_node_or_null("GunMesh") as MeshInstance3D
	if original_gun_mesh:
		original_gun_mesh.visible = false
		original_gun_mesh.mesh = null
		
	# Cria novo modelo procedural específico
	var new_model := build_weapon_model(weapon_id)
	new_model.name = "ProceduralWeaponModel"
	holder.add_child(new_model)
	
	# Reposiciona o Muzzle para a ponta exata do cano desta arma
	var muzzle = holder.get_node_or_null("Muzzle") as Marker3D
	if muzzle:
		muzzle.position = get_muzzle_pos(weapon_id)

## Construtor mestre de modelos por ID
static func build_weapon_model(weapon_id: String) -> Node3D:
	match weapon_id:
		"pistol":
			return _build_pistol()
		"magnum":
			return _build_magnum()
		"smg":
			return _build_smg()
		"rifle":
			return _build_rifle()
		"lmg":
			return _build_lmg()
		"shotgun":
			return _build_shotgun()
		"sniper":
			return _build_sniper()
		_:
			return _build_rifle()

## =============================================================================
## 1. PISTOLA PADRÃO (Glock / Tactical 9mm)
## Visual: Ferrolho em aço carbono escovado fosco, armação em polímero preto,
## ranhuras traseiras, guarda-mato tático e miras noturnas com ponto verde tritium.
## =============================================================================
static func _build_pistol() -> Node3D:
	var root := Node3D.new()
	
	var mat_slide = _get_mat("pistol_slide", Color(0.18, 0.19, 0.22), 0.75, 0.32)
	var mat_frame = _get_mat("pistol_frame", Color(0.11, 0.12, 0.13), 0.15, 0.75)
	var mat_barrel = _get_mat("pistol_barrel", Color(0.14, 0.14, 0.15), 0.85, 0.25)
	var mat_tritium = _get_mat("tritium_green", Color(0.25, 1.0, 0.35), 0.1, 0.2, Color(0.2, 1.0, 0.3), 3.0)
	var mat_white = _get_mat("sight_white", Color(0.9, 0.9, 0.9), 0.1, 0.4)
	
	# 1. Ferrolho (Slide) Principal
	_create_part(root, _box(Vector3(0.038, 0.042, 0.21)), Vector3(0, 0.021, -0.05), Vector3.ZERO, mat_slide, "Slide")
	# Chanfro superior do ferrolho
	_create_part(root, _box(Vector3(0.032, 0.010, 0.19)), Vector3(0, 0.044, -0.05), Vector3.ZERO, mat_slide, "SlideTop")
	# Janela de ejeção (top-right)
	_create_part(root, _box(Vector3(0.018, 0.016, 0.046)), Vector3(0.012, 0.032, -0.038), Vector3.ZERO, mat_barrel, "EjectionPort")
	
	# Ranhuras de aderência traseiras (serrations)
	for i in range(3):
		var z_off: float = 0.02 + (i * 0.014)
		_create_part(root, _box(Vector3(0.040, 0.030, 0.005)), Vector3(0, 0.022, z_off), Vector3.ZERO, mat_frame)
		
	# 2. Cano de Aço
	_create_part(root, _cylinder(0.009, 0.045), Vector3(0, 0.024, -0.165), Vector3(90, 0, 0), mat_barrel, "Barrel")
	
	# 3. Armação Inferior (Frame) com Trilho Picatinny
	_create_part(root, _box(Vector3(0.036, 0.024, 0.15)), Vector3(0, -0.008, -0.06), Vector3.ZERO, mat_frame, "Frame")
	
	# 4. Empunhadura Ergonômica (Grip)
	_create_part(root, _box(Vector3(0.034, 0.115, 0.046)), Vector3(0, -0.065, 0.012), Vector3(-14, 0, 0), mat_frame, "Grip")
	# Ressaltos anatômicos dianteiros (Finger Grooves)
	_create_part(root, _box(Vector3(0.035, 0.014, 0.010)), Vector3(0, -0.045, -0.008), Vector3(-14, 0, 0), mat_frame)
	_create_part(root, _box(Vector3(0.035, 0.014, 0.010)), Vector3(0, -0.075, 0.000), Vector3(-14, 0, 0), mat_frame)
	# Baseplate do carregador
	_create_part(root, _box(Vector3(0.036, 0.012, 0.052)), Vector3(0, -0.125, 0.025), Vector3(-14, 0, 0), mat_slide, "MagBase")
	
	# 5. Guarda-mato e Gatilho
	_create_part(root, _box(Vector3(0.024, 0.038, 0.062)), Vector3(0, -0.026, -0.018), Vector3.ZERO, mat_frame, "TriggerGuard")
	_create_part(root, _box(Vector3(0.008, 0.024, 0.008)), Vector3(0, -0.022, -0.015), Vector3(15, 0, 0), mat_barrel, "Trigger")
	
	# 6. Miras Noturnas com Ponto Verde Fluorescente (Tritium)
	# Alça de mira traseira (entalhe U com pontos brancos)
	_create_part(root, _box(Vector3(0.030, 0.010, 0.012)), Vector3(0, 0.053, 0.045), Vector3.ZERO, mat_slide, "RearSight")
	_create_part(root, _box(Vector3(0.006, 0.006, 0.004)), Vector3(-0.010, 0.054, 0.048), Vector3.ZERO, mat_white)
	_create_part(root, _box(Vector3(0.006, 0.006, 0.004)), Vector3(0.010, 0.054, 0.048), Vector3.ZERO, mat_white)
	# Massa de mira dianteira com ponto verde neon
	_create_part(root, _box(Vector3(0.010, 0.012, 0.012)), Vector3(0, 0.053, -0.145), Vector3.ZERO, mat_slide, "FrontSight")
	_create_part(root, _box(Vector3(0.006, 0.006, 0.005)), Vector3(0, 0.054, -0.142), Vector3.ZERO, mat_tritium, "FrontDot")
	
	return root

## =============================================================================
## 2. PISTOLA MAGNUM .50 (Desert Eagle Hand Cannon)
## Visual: Aço cromado maciço polido com reflexos metálicos brilhantes,
## compensador frontal com orifícios de escape duplos, cão exposto e empunhadura emborrachada preta.
## =============================================================================
static func _build_magnum() -> Node3D:
	var root := Node3D.new()
	
	var mat_chrome = _get_mat("magnum_chrome", Color(0.88, 0.89, 0.92), 0.95, 0.16)
	var mat_barrel_core = _get_mat("magnum_bore", Color(0.12, 0.12, 0.13), 0.85, 0.25)
	var mat_rubber = _get_mat("magnum_grip", Color(0.08, 0.09, 0.10), 0.05, 0.85)
	var mat_gold = _get_mat("magnum_gold", Color(0.88, 0.74, 0.25), 0.95, 0.20)
	var mat_orange_sight = _get_mat("sight_orange", Color(1.0, 0.35, 0.08), 0.1, 0.2, Color(1.0, 0.35, 0.08), 3.0)
	
	# 1. Slide Maciço em Aço Cromado
	_create_part(root, _box(Vector3(0.048, 0.056, 0.27)), Vector3(0, 0.028, -0.07), Vector3.ZERO, mat_chrome, "Slide")
	# Trilho Superior Picatinny com ranhuras
	_create_part(root, _box(Vector3(0.034, 0.010, 0.22)), Vector3(0, 0.058, -0.07), Vector3.ZERO, mat_chrome, "TopRail")
	for i in range(5):
		var z_cut: float = -0.15 + (i * 0.035)
		_create_part(root, _box(Vector3(0.036, 0.006, 0.012)), Vector3(0, 0.059, z_cut), Vector3.ZERO, mat_barrel_core)
		
	# 2. Compensador Frontal (Muzzle Brake Integrado com Portas de Escape)
	_create_part(root, _box(Vector3(0.048, 0.054, 0.055)), Vector3(0, 0.028, -0.225), Vector3.ZERO, mat_chrome, "Compensator")
	# Aberturas laterais do compensador
	_create_part(root, _box(Vector3(0.050, 0.020, 0.018)), Vector3(0, 0.034, -0.220), Vector3.ZERO, mat_barrel_core)
	_create_part(root, _box(Vector3(0.050, 0.020, 0.018)), Vector3(0, 0.034, -0.240), Vector3.ZERO, mat_barrel_core)
	# Furo de grande calibre .50 no cano
	_create_part(root, _cylinder(0.014, 0.06), Vector3(0, 0.028, -0.24), Vector3(90, 0, 0), mat_barrel_core, "CaliberBore")
	
	# 3. Armação Inferior Cromada
	_create_part(root, _box(Vector3(0.046, 0.034, 0.19)), Vector3(0, -0.012, -0.06), Vector3.ZERO, mat_chrome, "Frame")
	
	# 4. Cão de Combate Exposto (Hammer)
	_create_part(root, _box(Vector3(0.016, 0.034, 0.024)), Vector3(0, 0.044, 0.068), Vector3(25, 0, 0), mat_chrome, "Hammer")
	
	# 5. Empunhadura de Borracha Pesada (Rubber Grips)
	_create_part(root, _box(Vector3(0.044, 0.130, 0.058)), Vector3(0, -0.075, 0.018), Vector3(-15, 0, 0), mat_rubber, "Grip")
	# Placas anatômicas laterais da empunhadura
	_create_part(root, _box(Vector3(0.048, 0.105, 0.048)), Vector3(0, -0.072, 0.018), Vector3(-15, 0, 0), mat_rubber)
	# Medalhão dourado exclusivo na empunhadura
	_create_part(root, _cylinder(0.007, 0.050), Vector3(0, -0.065, 0.018), Vector3(0, 0, 90), mat_gold, "Medallion")
	
	# 6. Guarda-Mato Largo e Gatilho Espelhado
	_create_part(root, _box(Vector3(0.028, 0.044, 0.070)), Vector3(0, -0.030, -0.020), Vector3.ZERO, mat_chrome, "TriggerGuard")
	_create_part(root, _box(Vector3(0.010, 0.028, 0.010)), Vector3(0, -0.026, -0.018), Vector3(15, 0, 0), mat_chrome, "Trigger")
	
	# 7. Aparelho de Mira de Tiro Esportivo
	_create_part(root, _box(Vector3(0.032, 0.014, 0.016)), Vector3(0, 0.068, 0.055), Vector3.ZERO, mat_barrel_core, "RearTargetSight")
	_create_part(root, _box(Vector3(0.012, 0.015, 0.018)), Vector3(0, 0.068, -0.205), Vector3.ZERO, mat_chrome, "FrontSightRamp")
	_create_part(root, _box(Vector3(0.006, 0.006, 0.016)), Vector3(0, 0.069, -0.203), Vector3.ZERO, mat_orange_sight, "OrangeFiberDot")
	
	return root

## =============================================================================
## 3. SUBMETRALHADORA SMG (MP5 Tactical 9mm)
## Visual: Corpo tubular em aço naval escurecido, carregador curvo tipo banana,
## guarda-mão canelado, alavanca de manejo HK e mira circular em anel característico.
## =============================================================================
static func _build_smg() -> Node3D:
	var root := Node3D.new()
	
	var mat_receiver = _get_mat("smg_steel", Color(0.16, 0.18, 0.22), 0.70, 0.38)
	var mat_poly = _get_mat("smg_polymer", Color(0.10, 0.10, 0.12), 0.15, 0.80)
	var mat_mag = _get_mat("smg_mag", Color(0.22, 0.24, 0.26), 0.65, 0.42)
	var mat_cyan = _get_mat("smg_ring_sight", Color(0.3, 0.9, 1.0), 0.1, 0.2, Color(0.2, 0.85, 1.0), 3.0)
	
	# 1. Receptor Superior Tubular
	_create_part(root, _cylinder(0.025, 0.32), Vector3(0, 0.026, -0.09), Vector3(90, 0, 0), mat_receiver, "UpperTube")
	# Tubo de gás e alojamento do cocking lever
	_create_part(root, _cylinder(0.013, 0.26), Vector3(0, 0.046, -0.11), Vector3(90, 0, 0), mat_receiver, "GasTube")
	# Alavanca de manejo tática (charging handle) inclinada a 45° à esquerda
	_create_part(root, _box(Vector3(0.022, 0.010, 0.010)), Vector3(-0.020, 0.052, -0.18), Vector3(0, 0, 35), mat_poly, "CockHandle")
	
	# 2. Receptor Inferior & Magwell
	_create_part(root, _box(Vector3(0.038, 0.048, 0.17)), Vector3(0, -0.014, -0.04), Vector3.ZERO, mat_poly, "LowerReceiver")
	_create_part(root, _box(Vector3(0.032, 0.115, 0.042)), Vector3(0, -0.068, 0.015), Vector3(-20, 0, 0), mat_poly, "Grip")
	
	# 3. Carregador Curvo (Curved Banana Magazine)
	_create_part(root, _box(Vector3(0.026, 0.08, 0.040)), Vector3(0, -0.075, -0.07), Vector3(5, 0, 0), mat_mag, "MagUpper")
	_create_part(root, _box(Vector3(0.026, 0.09, 0.038)), Vector3(0, -0.145, -0.055), Vector3(16, 0, 0), mat_mag, "MagLower")
	
	# 4. Guarda-Mão Tático Estriado (Ribbed Handguard)
	_create_part(root, _box(Vector3(0.044, 0.046, 0.14)), Vector3(0, 0.015, -0.21), Vector3.ZERO, mat_poly, "Handguard")
	for i in range(4):
		var rib_z: float = -0.25 + (i * 0.028)
		_create_part(root, _box(Vector3(0.046, 0.048, 0.008)), Vector3(0, 0.015, rib_z), Vector3.ZERO, mat_poly)
		
	# 5. Cano Curto e Quebra-Chamas Canelado Tri-Lug
	_create_part(root, _cylinder(0.011, 0.09), Vector3(0, 0.020, -0.31), Vector3(90, 0, 0), mat_receiver, "Barrel")
	_create_part(root, _cylinder(0.014, 0.035), Vector3(0, 0.020, -0.355), Vector3(90, 0, 0), mat_receiver, "FlashHider")
	
	# 6. Coronha de Arame Retrátil (Collapsible Stock)
	_create_part(root, _box(Vector3(0.008, 0.008, 0.22)), Vector3(-0.020, 0.020, 0.02), Vector3.ZERO, mat_receiver)
	_create_part(root, _box(Vector3(0.008, 0.008, 0.22)), Vector3(0.020, 0.020, 0.02), Vector3.ZERO, mat_receiver)
	_create_part(root, _box(Vector3(0.040, 0.085, 0.016)), Vector3(0, 0.005, 0.13), Vector3.ZERO, mat_poly, "Buttpad")
	
	# 7. Aparelho de Pontaria em Anel Característico (Hooded Ring Sight)
	_create_part(root, _box(Vector3(0.026, 0.016, 0.016)), Vector3(0, 0.058, 0.04), Vector3.ZERO, mat_receiver, "RearDrumSight")
	# Anel Protetor Frontal (Sight Hood)
	_create_part(root, _cylinder(0.016, 0.012), Vector3(0, 0.056, -0.275), Vector3(90, 0, 0), mat_receiver, "HoodOuter")
	_create_part(root, _cylinder(0.010, 0.014), Vector3(0, 0.056, -0.275), Vector3(90, 0, 0), mat_poly, "HoodInnerHole")
	# Ponto de Mira Central em Ciano Neon
	_create_part(root, _box(Vector3(0.004, 0.012, 0.004)), Vector3(0, 0.054, -0.275), Vector3.ZERO, mat_cyan, "CyanSightPost")
	
	return root

## =============================================================================
## 4. RIFLE DE ASSALTO M4 (M4A1 Carbine com Holo Red Dot)
## Visual: Militar Two-Tone (Verde Oliva / Dark Tan no guarda-mão e coronha,
## receptor preto anodizado), cano 14.5" com birdcage, carregador STANAG curvo
## e mira holográfica tática com retículo Red Dot central iluminado.
## =============================================================================
static func _build_rifle() -> Node3D:
	var root := Node3D.new()
	
	var mat_receiver = _get_mat("m4_anodized", Color(0.14, 0.15, 0.17), 0.80, 0.30)
	var mat_furniture = _get_mat("m4_olive", Color(0.28, 0.32, 0.24), 0.25, 0.65) # Verde Oliva Tático
	var mat_barrel = _get_mat("m4_steel", Color(0.20, 0.21, 0.23), 0.85, 0.28)
	var mat_mag = _get_mat("m4_stanag", Color(0.26, 0.28, 0.30), 0.70, 0.38)
	var mat_rubber = _get_mat("m4_buttpad", Color(0.09, 0.09, 0.10), 0.05, 0.85)
	var mat_glass = _get_mat("holo_glass", Color(0.4, 0.8, 1.0, 0.35), 0.1, 0.1)
	var mat_red_dot = _get_mat("holo_red_dot", Color(1.0, 0.1, 0.1), 0.1, 0.1, Color(1.0, 0.15, 0.15), 4.5)
	
	# 1. Receptor Inferior & Magwell (Lower Receiver)
	_create_part(root, _box(Vector3(0.040, 0.065, 0.18)), Vector3(0, -0.010, -0.05), Vector3.ZERO, mat_receiver, "LowerReceiver")
	# 2. Receptor Superior com Trilho Superior (Upper Receiver)
	_create_part(root, _box(Vector3(0.038, 0.045, 0.20)), Vector3(0, 0.030, -0.06), Vector3.ZERO, mat_receiver, "UpperReceiver")
	# Defletor de estojos e botão de avanço manual (Forward Assist)
	_create_part(root, _box(Vector3(0.012, 0.018, 0.024)), Vector3(0.024, 0.034, -0.01), Vector3(0, 20, 0), mat_receiver)
	_create_part(root, _cylinder(0.008, 0.022), Vector3(0.024, 0.038, 0.025), Vector3(0, 0, 60), mat_receiver)
	
	# 3. Carregador Curvo STANAG 30 Tiros
	_create_part(root, _box(Vector3(0.026, 0.170, 0.056)), Vector3(0, -0.105, -0.07), Vector3(12, 0, 0), mat_mag, "Magazine")
	
	# 4. Empunhadura Anatômica M4
	_create_part(root, _box(Vector3(0.032, 0.120, 0.044)), Vector3(0, -0.065, 0.025), Vector3(-18, 0, 0), mat_furniture, "PistolGrip")
	
	# 5. Guarda-Mão Quad-Rail Tático (Handguard Verde Oliva)
	_create_part(root, _box(Vector3(0.044, 0.050, 0.250)), Vector3(0, 0.020, -0.265), Vector3.ZERO, mat_furniture, "Handguard")
	# Trilhos Picatinny nas 4 faces
	_create_part(root, _box(Vector3(0.034, 0.008, 0.250)), Vector3(0, 0.048, -0.265), Vector3.ZERO, mat_receiver) # Topo
	_create_part(root, _box(Vector3(0.034, 0.008, 0.250)), Vector3(0, -0.008, -0.265), Vector3.ZERO, mat_receiver) # Baixo
	_create_part(root, _box(Vector3(0.008, 0.036, 0.250)), Vector3(-0.024, 0.020, -0.265), Vector3.ZERO, mat_receiver) # Esquerda
	_create_part(root, _box(Vector3(0.008, 0.036, 0.250)), Vector3(0.024, 0.020, -0.265), Vector3.ZERO, mat_receiver) # Direita
	
	# 6. Cano Militar Longo 14.5" e Quebra-Chamas Birdcage
	_create_part(root, _cylinder(0.010, 0.22), Vector3(0, 0.020, -0.45), Vector3(90, 0, 0), mat_barrel, "Barrel")
	_create_part(root, _box(Vector3(0.020, 0.040, 0.020)), Vector3(0, 0.032, -0.42), Vector3.ZERO, mat_receiver, "GasBlock")
	_create_part(root, _cylinder(0.015, 0.045), Vector3(0, 0.020, -0.56), Vector3(90, 0, 0), mat_barrel, "FlashHider")
	
	# 7. Tubo Amortecedor e Coronha Telescópica Crane
	_create_part(root, _cylinder(0.014, 0.16), Vector3(0, 0.022, 0.12), Vector3(90, 0, 0), mat_receiver, "BufferTube")
	_create_part(root, _box(Vector3(0.042, 0.100, 0.140)), Vector3(0, -0.005, 0.18), Vector3.ZERO, mat_furniture, "CraneStock")
	_create_part(root, _box(Vector3(0.044, 0.104, 0.016)), Vector3(0, -0.005, 0.25), Vector3.ZERO, mat_rubber, "RecoilPad")
	
	# 8. Mira Holográfica Tática com Red Dot Central
	_create_part(root, _box(Vector3(0.036, 0.012, 0.065)), Vector3(0, 0.056, -0.06), Vector3.ZERO, mat_receiver, "OpticBase")
	# Armação externa protetora da mira (Hood)
	_create_part(root, _box(Vector3(0.040, 0.044, 0.065)), Vector3(0, 0.076, -0.06), Vector3.ZERO, mat_receiver, "OpticHood")
	# Abertura interna da janela óptica
	_create_part(root, _box(Vector3(0.030, 0.034, 0.070)), Vector3(0, 0.076, -0.06), Vector3.ZERO, mat_furniture, "OpticWindowCut")
	# Lente de Vidro Translúcida com ponto vermelho (Red Dot) centralizado
	_create_part(root, _box(Vector3(0.028, 0.030, 0.004)), Vector3(0, 0.076, -0.06), Vector3.ZERO, mat_glass, "OpticLens")
	_create_part(root, _box(Vector3(0.004, 0.004, 0.006)), Vector3(0, 0.076, -0.06), Vector3.ZERO, mat_red_dot, "RedDotReticle")
	
	return root

## =============================================================================
## 5. METRALHADORA PESADA LMG (M249 SAW Squad Automatic Weapon)
## Visual: Caixa de mecanismos reforçada com tampa de alimentação articulada,
## alça de transporte superior, protetor térmico perfurado, bipé tático dobrado,
## caixa de munição de 200 tiros verde oliva com fita de balas douradas visível!
## =============================================================================
static func _build_lmg() -> Node3D:
	var root := Node3D.new()
	
	var mat_receiver = _get_mat("lmg_steel", Color(0.12, 0.13, 0.15), 0.85, 0.28)
	var mat_box = _get_mat("lmg_ammo_box", Color(0.20, 0.26, 0.18), 0.20, 0.70) # Verde Militar Caixa
	var mat_barrel = _get_mat("lmg_barrel", Color(0.18, 0.19, 0.20), 0.80, 0.32)
	var mat_bullet = _get_mat("lmg_brass_bullet", Color(0.92, 0.76, 0.25), 0.95, 0.18) # Latão/Ouro
	var mat_link = _get_mat("lmg_belt_link", Color(0.10, 0.10, 0.10), 0.80, 0.40)
	var mat_poly = _get_mat("lmg_polymer", Color(0.08, 0.08, 0.09), 0.10, 0.85)
	
	# 1. Receptor Principal Robusto e Pesado
	_create_part(root, _box(Vector3(0.062, 0.080, 0.28)), Vector3(0, 0.010, -0.08), Vector3.ZERO, mat_receiver, "HeavyReceiver")
	# Tampa de alimentação superior articulada (Feed Tray Cover)
	_create_part(root, _box(Vector3(0.058, 0.024, 0.24)), Vector3(0, 0.054, -0.09), Vector3.ZERO, mat_receiver, "TopFeedCover")
	
	# 2. Alça de Transporte Superior (Carry Handle)
	_create_part(root, _box(Vector3(0.012, 0.055, 0.014)), Vector3(0.035, 0.080, -0.15), Vector3(0, 0, -25), mat_receiver)
	_create_part(root, _box(Vector3(0.014, 0.014, 0.095)), Vector3(0.048, 0.105, -0.12), Vector3.ZERO, mat_poly, "CarryGrip")
	
	# 3. Empunhadura de Pistola Pesada
	_create_part(root, _box(Vector3(0.036, 0.125, 0.048)), Vector3(0, -0.075, 0.03), Vector3(-15, 0, 0), mat_poly, "Grip")
	
	# 4. Caixa de Munição de 200 Tiros (Ammo Box Drum)
	_create_part(root, _box(Vector3(0.078, 0.125, 0.135)), Vector3(-0.022, -0.088, -0.08), Vector3.ZERO, mat_box, "AmmoBox")
	_create_part(root, _box(Vector3(0.080, 0.014, 0.137)), Vector3(-0.022, -0.030, -0.08), Vector3.ZERO, mat_receiver, "BoxBracket")
	
	# 5. Fita de Munição Visível com Balas de Ouro/Latão entrando no receptor
	for i in range(4):
		var b_z: float = -0.12 + (i * 0.024)
		_create_part(root, _cylinder(0.007, 0.028), Vector3(-0.038, 0.028, b_z), Vector3(0, 0, 90), mat_bullet)
		_create_part(root, _box(Vector3(0.010, 0.016, 0.012)), Vector3(-0.038, 0.028, b_z), Vector3.ZERO, mat_link)
		
	# 6. Blindagem Térmica Perfurada (Ventilated Heat Shield)
	_create_part(root, _box(Vector3(0.054, 0.058, 0.240)), Vector3(0, 0.020, -0.32), Vector3.ZERO, mat_receiver, "HeatShield")
	# Ranhuras de arrefecimento simuladas
	for i in range(4):
		var slot_z: float = -0.38 + (i * 0.038)
		_create_part(root, _box(Vector3(0.056, 0.012, 0.020)), Vector3(0, 0.044, slot_z), Vector3.ZERO, mat_barrel)
		_create_part(root, _box(Vector3(0.056, 0.012, 0.020)), Vector3(0, -0.004, slot_z), Vector3.ZERO, mat_barrel)
		
	# 7. Cano Pesado e Supressor Cônico de Flash
	_create_part(root, _cylinder(0.015, 0.32), Vector3(0, 0.020, -0.46), Vector3(90, 0, 0), mat_barrel, "HeavyBarrel")
	_create_part(root, _cylinder(0.022, 0.065), Vector3(0, 0.020, -0.63), Vector3(90, 0, 0), mat_barrel, "ConicalFlashSuppressor")
	
	# 8. Bipé Tático Dobrado (Folded Bipod)
	_create_part(root, _box(Vector3(0.046, 0.016, 0.020)), Vector3(0, -0.018, -0.38), Vector3.ZERO, mat_receiver, "BipodMount")
	_create_part(root, _cylinder(0.006, 0.20), Vector3(-0.022, -0.035, -0.32), Vector3(90, 0, 0), mat_receiver, "BipodLeft")
	_create_part(root, _cylinder(0.006, 0.20), Vector3(0.022, -0.035, -0.32), Vector3(90, 0, 0), mat_receiver, "BipodRight")
	_create_part(root, _box(Vector3(0.016, 0.008, 0.024)), Vector3(-0.022, -0.035, -0.22), Vector3.ZERO, mat_poly)
	_create_part(root, _box(Vector3(0.016, 0.008, 0.024)), Vector3(0.022, -0.035, -0.22), Vector3.ZERO, mat_poly)
	
	# 9. Coronha Pesada de Suporte (Clubfoot Machine Gun Stock)
	_create_part(root, _box(Vector3(0.048, 0.120, 0.180)), Vector3(0, -0.015, 0.16), Vector3.ZERO, mat_poly, "HeavyStock")
	# Barra de apoio de ombro superior
	_create_part(root, _box(Vector3(0.020, 0.008, 0.140)), Vector3(0, 0.048, 0.16), Vector3.ZERO, mat_receiver, "ShoulderRest")
	
	# 10. Aparelho de Pontaria Pesado
	_create_part(root, _box(Vector3(0.026, 0.024, 0.016)), Vector3(0, 0.075, 0.02), Vector3.ZERO, mat_receiver, "LadderSight")
	_create_part(root, _box(Vector3(0.014, 0.022, 0.016)), Vector3(0, 0.068, -0.42), Vector3.ZERO, mat_receiver, "FrontSightPost")
	
	return root

## =============================================================================
## 6. ESCOPETA TÁTICA (Tactical 12-Gauge Pump Shotgun)
## =============================================================================
static func _build_shotgun() -> Node3D:
	var root := Node3D.new()
	var mat_receiver = _get_mat("shotgun_steel", Color(0.16, 0.17, 0.18), 0.75, 0.35)
	var mat_poly = _get_mat("shotgun_poly", Color(0.10, 0.10, 0.11), 0.10, 0.80)
	var mat_shell = _get_mat("shotgun_shell_red", Color(0.85, 0.12, 0.12), 0.20, 0.40)
	var mat_brass = _get_mat("shotgun_brass", Color(0.90, 0.75, 0.25), 0.95, 0.20)
	
	# Receptor da escopeta
	_create_part(root, _box(Vector3(0.044, 0.062, 0.22)), Vector3(0, 0.010, -0.06), Vector3.ZERO, mat_receiver, "Receiver")
	# Cano calibre 12 longo
	_create_part(root, _cylinder(0.014, 0.36), Vector3(0, 0.024, -0.34), Vector3(90, 0, 0), mat_receiver, "12GaugeBarrel")
	# Tubo de munição inferior
	_create_part(root, _cylinder(0.013, 0.32), Vector3(0, -0.005, -0.32), Vector3(90, 0, 0), mat_receiver, "MagTube")
	# Pump action slide com estrias
	_create_part(root, _box(Vector3(0.046, 0.044, 0.14)), Vector3(0, -0.005, -0.28), Vector3.ZERO, mat_poly, "PumpSlide")
	# Cartucheira lateral com 4 cartuchos vermelhos com base dourada
	for i in range(4):
		var cz: float = -0.12 + (i * 0.026)
		_create_part(root, _cylinder(0.009, 0.028), Vector3(0.026, 0.010, cz), Vector3(0, 0, 90), mat_shell)
		_create_part(root, _cylinder(0.010, 0.008), Vector3(0.038, 0.010, cz), Vector3(0, 0, 90), mat_brass)
	# Empunhadura e coronha de combate
	_create_part(root, _box(Vector3(0.034, 0.115, 0.046)), Vector3(0, -0.065, 0.02), Vector3(-18, 0, 0), mat_poly, "Grip")
	_create_part(root, _box(Vector3(0.040, 0.090, 0.160)), Vector3(0, -0.015, 0.15), Vector3.ZERO, mat_poly, "Stock")
	
	return root

## =============================================================================
## 7. RIFLE DE PRECISÃO SNIPER (AWP Style Arctic Warfare)
## =============================================================================
static func _build_sniper() -> Node3D:
	var root := Node3D.new()
	var mat_receiver = _get_mat("sniper_receiver", Color(0.12, 0.13, 0.14), 0.85, 0.25)
	var mat_chassis = _get_mat("sniper_chassis", Color(0.18, 0.28, 0.20), 0.20, 0.65) # Verde Militar AWP
	var mat_barrel = _get_mat("sniper_barrel", Color(0.16, 0.17, 0.18), 0.80, 0.30)
	var mat_scope = _get_mat("sniper_scope", Color(0.10, 0.10, 0.11), 0.60, 0.35)
	var mat_lens = _get_mat("sniper_lens", Color(0.2, 0.7, 1.0, 0.4), 0.1, 0.1)
	
	# Chassi estilo Arctic Warfare
	_create_part(root, _box(Vector3(0.046, 0.060, 0.42)), Vector3(0, -0.005, -0.16), Vector3.ZERO, mat_chassis, "AWPChassis")
	# Cano de precisão longo bull barrel
	_create_part(root, _cylinder(0.012, 0.46), Vector3(0, 0.025, -0.48), Vector3(90, 0, 0), mat_barrel, "BullBarrel")
	# Quebra-chamas massivo com portas laterais
	_create_part(root, _box(Vector3(0.034, 0.034, 0.065)), Vector3(0, 0.025, -0.71), Vector3.ZERO, mat_barrel, "MuzzleBrake")
	# Alavanca do ferrolho (Bolt Action)
	_create_part(root, _cylinder(0.006, 0.035), Vector3(0.032, 0.035, 0.02), Vector3(0, 0, 70), mat_receiver)
	_create_part(root, _cylinder(0.012, 0.014), Vector3(0.048, 0.045, 0.02), Vector3.ZERO, mat_receiver, "BoltKnob")
	# Coronha com furo para polegar (Thumbhole Stock)
	_create_part(root, _box(Vector3(0.044, 0.115, 0.200)), Vector3(0, -0.015, 0.18), Vector3.ZERO, mat_chassis, "ThumbholeStock")
	# Luneta de Alta Precisão (High Power Sniper Scope)
	_create_part(root, _cylinder(0.018, 0.22), Vector3(0, 0.075, -0.06), Vector3(90, 0, 0), mat_scope, "ScopeBody")
	_create_part(root, _cylinder(0.025, 0.045), Vector3(0, 0.075, -0.18), Vector3(90, 0, 0), mat_scope, "ObjectiveLensHousing")
	_create_part(root, _cylinder(0.022, 0.004), Vector3(0, 0.075, -0.20), Vector3(90, 0, 0), mat_lens, "ObjectiveLens")
	_create_part(root, _cylinder(0.020, 0.035), Vector3(0, 0.075, 0.06), Vector3(90, 0, 0), mat_scope, "OcularLensHousing")
	# Torres de ajuste de elevação e vento
	_create_part(root, _cylinder(0.010, 0.020), Vector3(0, 0.098, -0.06), Vector3.ZERO, mat_scope, "ElevationTurret")
	_create_part(root, _cylinder(0.010, 0.020), Vector3(0.022, 0.075, -0.06), Vector3(0, 0, 90), mat_scope, "WindageTurret")
	
	return root
