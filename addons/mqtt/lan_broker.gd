class_name MQTTLANBroker
extends Node

signal broker_available(url: String, hosted_here: bool)
signal failed(message: String)
signal diagnostic(message: String)

const SimulatedBroker = preload("res://addons/mqtt/simulated_broker.gd")
const PROTOCOL_NAME := "godot-mqtt-lan"
const PROTOCOL_VERSION := 1

enum State { STOPPED, SEARCHING, ELECTING, HOSTING, USING_REMOTE, FAILED }

@export var discovery_port := 1884
@export var broker_port := 1883
@export var discovery_seconds := 1.0
@export var election_seconds := 0.8
@export var announce_seconds := 0.25
@export var verbose := true

var state := State.STOPPED
var broker_url := ""
var node_id := ""

var _receiver: UDPServer
var _broadcaster: PacketPeerUDP
var _local_probe: StreamPeerTCP
var _broker: MQTTSimulatedBroker
var _can_receive_broadcasts := false
var _candidates: Dictionary = {}
var _phase_ends_msec := 0
var _next_announce_msec := 0
var _fault_profile: Dictionary = {}


func configure_faults(options: Dictionary = {}) -> void:
	_fault_profile = options.duplicate(true)
	if _broker != null:
		_broker.configure_faults(_fault_profile)


func hold_deliveries(duration_ms: int) -> int:
	if _broker == null:
		return ERR_UNAVAILABLE
	_broker.hold_deliveries(duration_ms)
	return OK


func get_fault_counters() -> Dictionary:
	return _broker.get_fault_counters() if _broker != null else {}


func start() -> int:
	if state != State.STOPPED:
		return ERR_ALREADY_IN_USE
	if OS.has_feature("web"):
		return _fail("LAN broker discovery is unavailable in web exports")
	var error := _open_udp()
	if error != OK:
		return error
	node_id = _make_node_id()
	_begin_local_probe()
	state = State.SEARCHING
	_phase_ends_msec = Time.get_ticks_msec() + int(discovery_seconds * 1000.0)
	_send_probe()
	set_process(true)
	_report("Looking for a LAN MQTT broker")
	return OK


func start_hosting() -> int:
	if state != State.STOPPED:
		return ERR_ALREADY_IN_USE
	if OS.has_feature("web"):
		return _fail("The simulated broker is unavailable in web exports")
	var error := _open_udp()
	if error != OK:
		return error
	node_id = _make_node_id()
	set_process(true)
	return _start_broker(false)


func stop() -> void:
	if _broker != null:
		_broker.stop()
		_broker.queue_free()
		_broker = null
	if _receiver != null:
		_receiver.stop()
		_receiver = null
	_broadcaster = null
	if _local_probe != null:
		_local_probe.disconnect_from_host()
		_local_probe = null
	_can_receive_broadcasts = false
	state = State.STOPPED
	broker_url = ""
	set_process(false)


func is_hosting() -> bool:
	return state == State.HOSTING


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	_poll_local_probe()
	_receive_packets()
	var now := Time.get_ticks_msec()
	match state:
		State.SEARCHING:
			if now >= _phase_ends_msec:
				if _can_receive_broadcasts:
					state = State.ELECTING
					_candidates = {node_id: true}
					_phase_ends_msec = now + int(election_seconds * 1000.0)
					_next_announce_msec = 0
				else:
					_phase_ends_msec = now + int(discovery_seconds * 1000.0)
					_send_probe()
		State.ELECTING:
			if now >= _next_announce_msec:
				_send_broadcast("candidate")
				_next_announce_msec = now + int(announce_seconds * 1000.0)
			if now >= _phase_ends_msec:
				_finish_election()
		State.HOSTING:
			if now >= _next_announce_msec:
				_send_broadcast("offer", broker_port)
				_next_announce_msec = now + int(announce_seconds * 1000.0)


func _open_udp() -> int:
	_receiver = UDPServer.new()
	var error := _receiver.listen(discovery_port)
	if error != OK:
		_report("UDP port %d is already in use; joining through a probe socket" % discovery_port)
		_receiver = null
	else:
		_can_receive_broadcasts = true
	_broadcaster = PacketPeerUDP.new()
	error = _broadcaster.bind(0)
	if error != OK:
		return _fail("Could not open UDP probe socket (error %d)" % error)
	_broadcaster.set_broadcast_enabled(true)
	error = _broadcaster.set_dest_address("255.255.255.255", discovery_port)
	if error != OK:
		_receiver.stop()
		_receiver = null
		_broadcaster = null
		return _fail("Could not configure UDP broadcast (error %d)" % error)
	return OK


func _begin_local_probe() -> void:
	_local_probe = StreamPeerTCP.new()
	var error := _local_probe.connect_to_host("127.0.0.1", broker_port)
	if error != OK:
		_local_probe = null


func _poll_local_probe() -> void:
	if _local_probe == null or state != State.SEARCHING:
		return
	_local_probe.poll()
	match _local_probe.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			_local_probe.disconnect_from_host()
			_local_probe = null
			_use_offer("127.0.0.1", broker_port)
		StreamPeerTCP.STATUS_ERROR:
			_local_probe = null


func _receive_packets() -> void:
	if _receiver != null:
		_receiver.poll()
		while _receiver.is_connection_available():
			var peer := _receiver.take_connection()
			while peer.get_available_packet_count() > 0:
				_handle_message(_decode_message(peer.get_packet()), peer.get_packet_ip(), peer)
	while _broadcaster.get_available_packet_count() > 0:
		_handle_message(_decode_message(_broadcaster.get_packet()), _broadcaster.get_packet_ip())


func _handle_message(message: Dictionary, address: String, reply_peer: PacketPeerUDP = null) -> void:
	if message.is_empty() or message.get("node_id", "") == node_id:
		return
	var kind: String = message.kind
	if kind == "offer":
		_use_offer(address, int(message.get("port", 0)))
	elif kind == "probe" and state == State.HOSTING:
		if reply_peer != null:
			reply_peer.put_packet(_encode_message("offer", broker_port))
		_send_broadcast("offer", broker_port)
	elif kind == "candidate" and state == State.ELECTING:
		_candidates[message.node_id] = true


func _finish_election() -> void:
	var candidate_ids := _candidates.keys()
	candidate_ids.sort()
	if candidate_ids.is_empty() or candidate_ids[0] == node_id:
		_start_broker()
	else:
		state = State.SEARCHING
		_phase_ends_msec = Time.get_ticks_msec() + int(discovery_seconds * 1000.0)
		_report("Waiting for elected broker %s" % candidate_ids[0])


func _start_broker(join_existing: bool = true) -> int:
	if _local_probe != null:
		_local_probe.disconnect_from_host()
		_local_probe = null
	_broker = SimulatedBroker.new()
	_broker.verbose = verbose
	add_child(_broker)
	if not _fault_profile.is_empty():
		_broker.configure_faults(_fault_profile)
	var error := _broker.start(broker_port)
	if error != OK:
		_broker.queue_free()
		_broker = null
		if join_existing:
			state = State.SEARCHING
			_phase_ends_msec = Time.get_ticks_msec() + int(discovery_seconds * 1000.0)
			_begin_local_probe()
			_report("TCP port %d is already in use; checking for the elected broker" % broker_port)
			return OK
		return _fail("Could not start the simulated broker on TCP port %d" % broker_port)
	state = State.HOSTING
	broker_url = "tcp://127.0.0.1:%d" % broker_port
	_next_announce_msec = 0
	_report("Hosting the LAN MQTT broker")
	broker_available.emit(broker_url, true)
	return OK


func _use_offer(address: String, offered_port: int) -> void:
	if offered_port < 1 or offered_port > 65535:
		return
	if state == State.HOSTING or state == State.USING_REMOTE:
		return
	state = State.USING_REMOTE
	broker_url = "tcp://%s:%d" % [address, offered_port]
	if _local_probe != null:
		_local_probe.disconnect_from_host()
		_local_probe = null
	_report("Using LAN MQTT broker at %s" % broker_url)
	broker_available.emit(broker_url, false)


func _send_broadcast(kind: String, offered_port: int = 0) -> void:
	_broadcaster.set_dest_address("255.255.255.255", discovery_port)
	var error := _broadcaster.put_packet(_encode_message(kind, offered_port))
	if error != OK:
		_report("UDP broker discovery send failed (error %d)" % error)


func _send_probe() -> void:
	_send_broadcast("probe")
	_broadcaster.set_dest_address("127.0.0.1", discovery_port)
	var error := _broadcaster.put_packet(_encode_message("probe"))
	if error != OK:
		_report("Local broker discovery probe failed (error %d)" % error)


func _encode_message(kind: String, offered_port: int = 0) -> PackedByteArray:
	var message := {
		"protocol": PROTOCOL_NAME,
		"version": PROTOCOL_VERSION,
		"kind": kind,
		"node_id": node_id,
	}
	if kind == "offer":
		message.port = offered_port
	return JSON.stringify(message).to_utf8_buffer()


func _decode_message(packet: PackedByteArray) -> Dictionary:
	var value = JSON.parse_string(packet.get_string_from_utf8())
	if not value is Dictionary:
		return {}
	if value.get("protocol") != PROTOCOL_NAME or value.get("version") != PROTOCOL_VERSION:
		return {}
	if not value.get("kind") in ["probe", "candidate", "offer"]:
		return {}
	if not value.get("node_id") is String or value.node_id.is_empty():
		return {}
	return value


func _make_node_id() -> String:
	return "%016x-%d" % [randi(), Time.get_ticks_usec()]


func _fail(message: String) -> int:
	state = State.FAILED
	set_process(false)
	push_error(message)
	failed.emit(message)
	return FAILED


func _report(message: String) -> void:
	if verbose:
		print(message)
	diagnostic.emit(message)
