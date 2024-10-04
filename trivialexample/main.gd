extends Node

@export var SERVER_URL = "127.0.0.1"
@export var SERVER_PORT = 8009

var user = load("res://user.tscn")

var mic_capture : AudioEffectOpusChunked

var users = {} # {Peer ID: AudioStreamPlayer}

var packets_received = 0
var packets_sent = 0

func _ready():
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	
	assert ($AudioStreamPlayer.bus == "Mic")
	var mic_bus = AudioServer.get_bus_index("Mic")
	mic_capture = AudioServer.get_bus_effect(mic_bus, 0)
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(SERVER_PORT)
	if err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE:
		peer.close()
		err = peer.create_client(SERVER_URL, SERVER_PORT)
		print("Created client ", ("Error %d" % err if err else ""))
	else:
		print("Created server ", ("Error %d" % err if err else ""))
		set_process(false)
		AudioServer.set_bus_effect_enabled(mic_bus, 0, false)
	multiplayer.multiplayer_peer = peer

func _peer_connected(id):
	print("Peer connected with ID ", id)
	users[id] = user.instantiate()
	add_child(users[id])
	
func _peer_disconnected(id):
	print("Peer disconnected with ID ", id)
	users[id].queue_free()
	users.erase(id)
	
func _connected_to_server():
	print("Connected to server ", SERVER_URL, ":", SERVER_PORT)
	
func _connection_failed():
	print("Failed to connect to server ", SERVER_URL, ":", SERVER_PORT)
	
func _server_disconnected():
	print("Server disconnected.")
	
@rpc("any_peer", "unreliable")
func _voice_packet_received(packet):
	packets_received += 1
	if (packets_received % 100) == 0:
		print("Packets received: ", packets_received, " from id ", multiplayer.get_unique_id())
	var sender_id = multiplayer.get_remote_sender_id()
	users[sender_id].stream.push_opus_packet(packet, 0, 0)

func _process(_delta):
	while mic_capture.chunk_available():
		var packet = mic_capture.read_opus_packet(PackedByteArray())
		mic_capture.drop_chunk()
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_voice_packet_received.rpc(packet)
			packets_sent += 1
			if (packets_sent % 100) == 0:
				print("Packets sent: ", packets_sent, " from id ", multiplayer.get_unique_id())
