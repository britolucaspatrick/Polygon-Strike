class_name NetworkManager
extends Node

## Sinais de Gerenciamento de Rede
signal server_started(local_ip: String, port: int)
signal client_connected_ok()
signal client_connection_failed(reason: String)
signal server_disconnected_msg()
signal peer_joined(id: int, player_data: Dictionary)
signal peer_left(id: int)
signal upnp_finished(success: bool, ext_ip: String, message: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 10

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var is_network_active: bool = false
var current_port: int = DEFAULT_PORT

var local_ip_address: String = "127.0.0.1"
var public_ip_address: String = ""
var upnp_thread: Thread = null

# Dados dos jogadores na sala: peer_id -> { "name": String, "team": String }
var lobby_players: Dictionary = {}

func _ready() -> void:
	local_ip_address = _detect_local_ip()

## Detecta o endereço IP local na rede Wi-Fi / Ethernet
func _detect_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		# Procura IPs locais típicos IPv4 (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
		if addr.begins_with("192.168.") or addr.begins_with("10.") or (addr.begins_with("172.") and not addr.contains(":")):
			return addr
	return "127.0.0.1"

## Inicia um Servidor (Host) na máquina local
func host_server(port: int = DEFAULT_PORT, use_upnp: bool = true, host_name: String = "Você", host_team: String = "blue") -> Dictionary:
	current_port = port
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		var err_msg = "Falha ao criar servidor na porta %d (Código: %d)" % [port, error]
		return {"success": false, "message": err_msg}
		
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_network_active = true
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Registra o Host no lobby (ID 1 no Godot)
	lobby_players[1] = {
		"name": host_name,
		"team": host_team
	}
	
	if use_upnp:
		_start_upnp_discovery(port)
		
	server_started.emit(local_ip_address, port)
	return {"success": true, "local_ip": local_ip_address, "port": port}

## Conecta a um servidor existente como Cliente (Join)
func join_server(address: String, port: int = DEFAULT_PORT, player_name: String = "Jogador", player_team: String = "red") -> void:
	current_port = port
	peer = ENetMultiplayerPeer.new()
	var clean_addr = address.strip_edges()
	if clean_addr.is_empty():
		clean_addr = "127.0.0.1"
		
	var error = peer.create_client(clean_addr, port)
	if error != OK:
		client_connection_failed.emit("Falha ao inicializar conexão para %s:%d" % [clean_addr, port])
		return
		
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_network_active = true
	
	# Guarda dados locais para enviar ao host após conectar
	var local_id = multiplayer.get_unique_id()
	lobby_players[local_id] = {
		"name": player_name,
		"team": player_team
	}
	
	multiplayer.connected_to_server.connect(_on_connected_to_server.bind(player_name, player_team))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## Dispara configuração de UPnP em uma Thread para não travar a interface
func _start_upnp_discovery(port: int) -> void:
	if upnp_thread and upnp_thread.is_alive():
		upnp_thread.wait_to_finish()
		
	upnp_thread = Thread.new()
	upnp_thread.start(_run_upnp_background.bind(port))

func _run_upnp_background(port: int) -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		err = upnp.discover(2000, 2, "")
		
	if err == UPNP.UPNP_RESULT_SUCCESS:
		var gateway := upnp.get_gateway()
		if gateway and gateway.is_valid_gateway():
			var map_udp := upnp.add_port_mapping(port, port, "PolygonStrikeUDP", "UDP")
			var map_tcp := upnp.add_port_mapping(port, port, "PolygonStrikeTCP", "TCP")
			var ext_ip: String = upnp.query_external_address()
			
			if map_udp == UPNP.UPNP_RESULT_SUCCESS or map_tcp == UPNP.UPNP_RESULT_SUCCESS:
				public_ip_address = ext_ip
				call_deferred("emit_signal", "upnp_finished", true, ext_ip, "✅ UPnP Ativo: Porta %d aberta! IP Público: %s" % [port, ext_ip])
				return
				
	call_deferred("emit_signal", "upnp_finished", false, "", "ℹ️ UPnP não ativado no roteador (usando Rede Local Wi-Fi)")

## Callbacks do Multiplayer
func _on_peer_connected(id: int) -> void:
	print("[REDE] Novo peer conectado ao servidor: %d" % id)
	# Solicita que o novo cliente envie seus dados (nome e time)
	rpc_id(id, "request_client_info")

func _on_peer_disconnected(id: int) -> void:
	print("[REDE] Peer desconectado: %d" % id)
	if lobby_players.has(id):
		lobby_players.erase(id)
	peer_left.emit(id)

func _on_connected_to_server(p_name: String, p_team: String) -> void:
	print("[REDE] Conexão bem-sucedida com o servidor!")
	client_connected_ok.emit()
	var my_id = multiplayer.get_unique_id()
	# Envia dados locais para o Host
	rpc_id(1, "register_player_info", my_id, p_name, p_team)

func _on_connection_failed() -> void:
	print("[REDE] Falha ao conectar ao servidor.")
	client_connection_failed.emit("Não foi possível conectar ao servidor. Verifique o IP e a porta.")
	_cleanup()

func _on_server_disconnected() -> void:
	print("[REDE] Servidor desconectou.")
	server_disconnected_msg.emit()
	_cleanup()

## RPCs de Sincronização do Lobby
@rpc("any_peer")
func request_client_info() -> void:
	var my_id = multiplayer.get_unique_id()
	var my_data: Dictionary = lobby_players.get(my_id, {"name": "Jogador", "team": "red"})
	rpc_id(1, "register_player_info", my_id, my_data.get("name", "Jogador"), my_data.get("team", "red"))

@rpc("any_peer")
func register_player_info(peer_id: int, player_name: String, player_team: String) -> void:
	if not is_host:
		return
	lobby_players[peer_id] = {
		"name": player_name,
		"team": player_team
	}
	# Replica a lista atualizada de jogadores para todos os peers
	rpc("sync_lobby_players", lobby_players)
	peer_joined.emit(peer_id, lobby_players[peer_id])

@rpc("call_local")
func sync_lobby_players(updated_players: Dictionary) -> void:
	lobby_players = updated_players

func _cleanup() -> void:
	is_network_active = false
	is_host = false
	lobby_players.clear()
	if peer:
		peer.close()
		peer = null
	if upnp_thread and upnp_thread.is_alive():
		upnp_thread.wait_to_finish()
