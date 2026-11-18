class_name AudioManagerClass
extends Node

## Gerenciador Central de Áudio Procedural
## Sintetiza internamente todos os efeitos sonoros em memória (PCM 16-bit)
## sem depender de arquivos ou assets de áudio externos.

var sounds: Dictionary = {}
var players_2d: Array[AudioStreamPlayer] = []
var players_3d: Array[AudioStreamPlayer3D] = []

const POOL_SIZE_2D: int = 10
const POOL_SIZE_3D: int = 14
const MIX_RATE: int = 22050

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_synthesize_all_sounds()
	_create_audio_pools()
	print("[AUDIO] Sistema de áudio procedural inicializado com %d efeitos sonoros." % sounds.size())

## Cria pools de players 2D e 3D para suportar múltiplos sons simultâneos
func _create_audio_pools() -> void:
	for i in range(POOL_SIZE_2D):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		players_2d.append(p)
		
	for i in range(POOL_SIZE_3D):
		var p3d := AudioStreamPlayer3D.new()
		p3d.bus = &"Master"
		p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3d.unit_size = 7.0
		p3d.max_distance = 250.0
		add_child(p3d)
		players_3d.append(p3d)

## Executa um som 2D (UI, armas do jogador, feedback estéreo)
func play(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
		
	var stream: AudioStreamWAV = sounds[sound_name]
	for p in players_2d:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return
			
	# Se todos estiverem ocupados, reaproveita o primeiro
	var fallback: AudioStreamPlayer = players_2d[0]
	fallback.stream = stream
	fallback.volume_db = volume_db
	fallback.pitch_scale = pitch_scale
	fallback.play()

## Executa um som 3D posicional no espaço (tiros de bots, explosões, passos)
func play_spatial(sound_name: String, global_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_dist: float = 200.0) -> void:
	if not sounds.has(sound_name):
		return
		
	var stream: AudioStreamWAV = sounds[sound_name]
	for p3d in players_3d:
		if not p3d.playing:
			p3d.global_position = global_pos
			p3d.max_distance = max_dist
			p3d.volume_db = volume_db
			p3d.pitch_scale = pitch_scale
			p3d.stream = stream
			p3d.play()
			return
			
	var fallback: AudioStreamPlayer3D = players_3d[0]
	fallback.global_position = global_pos
	fallback.max_distance = max_dist
	fallback.volume_db = volume_db
	fallback.pitch_scale = pitch_scale
	fallback.stream = stream
	fallback.play()

## Sintetizador PCM procedual para efeitos sonoros
func _synthesize_all_sounds() -> void:
	var create_stream = func(duration: float, generator: Callable) -> AudioStreamWAV:
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = MIX_RATE
		stream.stereo = false
		var sample_count: int = int(duration * MIX_RATE)
		var bytes := PackedByteArray()
		bytes.resize(sample_count * 2)
		for i in range(sample_count):
			var t: float = float(i) / float(MIX_RATE)
			var s: float = clampf(generator.call(t, duration), -1.0, 1.0)
			bytes.encode_s16(i * 2, int(s * 32767.0))
		stream.data = bytes
		return stream

	# 1. Tiro de Pistola
	sounds["shoot_pistol"] = create_stream.call(0.16, func(t: float, d: float) -> float:
		var env: float = exp(-t * 26.0)
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.75
		var freq: float = lerp(270.0, 60.0, t / d)
		var tone: float = sin(t * freq * TAU) * 0.55
		return (noise + tone) * env
	)
	
	# 2. Tiro de Submetralhadora SMG
	sounds["shoot_smg"] = create_stream.call(0.11, func(t: float, d: float) -> float:
		var env: float = exp(-t * 34.0)
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 55.0) * 0.8
		var freq: float = lerp(340.0, 85.0, t / d)
		var tone: float = sin(t * freq * TAU) * 0.45
		return (noise + tone) * env
	)
	
	# 3. Tiro de Rifle M4 / Metralhadora
	sounds["shoot_rifle"] = create_stream.call(0.16, func(t: float, d: float) -> float:
		var env: float = exp(-t * 22.0)
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 38.0) * 0.85
		var freq: float = lerp(230.0, 50.0, t / d)
		var tone: float = sin(t * freq * TAU) * 0.65
		return (noise + tone) * env
	)
	
	# 4. Tiro de Magnum .50
	sounds["shoot_magnum"] = create_stream.call(0.35, func(t: float, d: float) -> float:
		var env: float = exp(-t * 11.0)
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 22.0) * 0.9
		var freq: float = lerp(210.0, 32.0, t / d)
		var tone: float = sin(t * freq * TAU) * 0.8
		return (noise + tone) * env
	)
	
	# 5. Clique de Arma sem Munição (Dry Fire)
	sounds["empty_click"] = create_stream.call(0.045, func(t: float, _d: float) -> float:
		var env: float = exp(-t * 110.0)
		var tone: float = sin(t * 1300.0 * TAU) * 0.55
		var noise: float = (randf() * 2.0 - 1.0) * 0.45
		return (tone + noise) * env
	)
	
	# 6. Recarga de Arma (Clipe mecânico)
	sounds["reload"] = create_stream.call(0.38, func(t: float, _d: float) -> float:
		var s: float = 0.0
		if t < 0.10:
			s = (randf() * 2.0 - 1.0) * exp(-t * 70.0) * 0.6 + sin(t * 850.0 * TAU) * exp(-t * 45.0) * 0.4
		elif t > 0.18 and t < 0.32:
			var t2: float = t - 0.18
			s = (randf() * 2.0 - 1.0) * exp(-t2 * 60.0) * 0.7 + sin(t2 * 1150.0 * TAU) * exp(-t2 * 40.0) * 0.5
		return s
	)
	
	# 7. Acerto de Tiro (Hitmarker Ping)
	sounds["hit"] = create_stream.call(0.075, func(t: float, _d: float) -> float:
		var env: float = exp(-t * 55.0)
		return (sin(t * 1650.0 * TAU) * 0.6 + sin(t * 2450.0 * TAU) * 0.4) * env
	)
	
	# 8. Acerto de Tiro na Cabeça (Headshot Ding + Crunch)
	sounds["headshot"] = create_stream.call(0.20, func(t: float, _d: float) -> float:
		var env: float = exp(-t * 20.0)
		var crunch: float = (randf() * 2.0 - 1.0) * exp(-t * 75.0) * 0.55
		var bell: float = (sin(t * 1980.0 * TAU) * 0.65 + sin(t * 2970.0 * TAU) * 0.35) * 0.75
		return (bell + crunch) * env
	)
	
	# 9. Explosão de Granada
	sounds["explosion"] = create_stream.call(0.90, func(t: float, d: float) -> float:
		var env: float = exp(-t * 4.2)
		var rumble: float = sin(t * lerp(120.0, 28.0, t / d) * TAU) * 0.65
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 6.5) * 0.65
		return (rumble + noise) * env
	)
	
	# 10. Lançamento de Granada / Pino
	sounds["grenade_throw"] = create_stream.call(0.18, func(t: float, _d: float) -> float:
		var click: float = sin(t * 1400.0 * TAU) * exp(-t * 90.0) * 0.5
		var whoosh: float = (randf() * 2.0 - 1.0) * sin(t * 22.0) * exp(-t * 18.0) * 0.4
		return click + whoosh
	)
	
	# 11. Compra Efetuada (Caixa Registradora / Moedas)
	sounds["buy"] = create_stream.call(0.24, func(t: float, _d: float) -> float:
		var tone: float = 0.0
		if t < 0.11:
			tone = sin(t * 1046.5 * TAU) * exp(-t * 18.0)
		else:
			var t2: float = t - 0.11
			tone = sin(t2 * 1318.5 * TAU) * exp(-t2 * 16.0)
		return tone * 0.65
	)
	
	# 12. Erro de Compra / Dinheiro Insuficiente
	sounds["buy_error"] = create_stream.call(0.14, func(t: float, _d: float) -> float:
		var env: float = exp(-t * 15.0)
		var buzz: float = 1.0 if sin(t * 145.0 * TAU) > 0.0 else -1.0
		return buzz * 0.35 * env
	)
	
	# 13. Cura na Base (Arpeggio Suave em Dó Maior)
	sounds["heal"] = create_stream.call(0.42, func(t: float, _d: float) -> float:
		var step: int = int(t / 0.10)
		var freqs = [523.25, 659.25, 783.99, 1046.50]
		var f: float = freqs[mini(step, 3)]
		var sub_t: float = fmod(t, 0.10)
		return sin(t * f * TAU) * exp(-sub_t * 12.0) * 0.45
	)
	
	# 14. Abate Confirmado (Trompete / Tom de Vitória)
	sounds["kill"] = create_stream.call(0.28, func(t: float, d: float) -> float:
		var env: float = exp(-t * 10.0)
		var f: float = lerp(440.0, 660.0, t / d)
		return (sin(t * f * TAU) * 0.5 + sin(t * (f * 1.5) * TAU) * 0.35) * env
	)
	
	# 15. Passos (Footsteps)
	sounds["footstep"] = create_stream.call(0.08, func(t: float, _d: float) -> float:
		var env: float = exp(-t * 48.0)
		var thud: float = sin(t * 85.0 * TAU) * 0.5
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 65.0) * 0.35
		return (thud + noise) * env
	)
