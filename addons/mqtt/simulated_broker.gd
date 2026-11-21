class_name MQTTSimulatedBroker
extends Node

signal broker_started(port: int)
signal broker_stopped
signal client_connected(client_id: String)
signal client_disconnected(client_id: String, unexpected: bool)
signal diagnostic(message: String)

const CP_CONNECT = 0x10
const CP_CONNACK = 0x20
const CP_PUBLISH = 0x30
const CP_PUBACK = 0x40
const CP_SUBSCRIBE = 0x82
const CP_SUBACK = 0x90
const CP_UNSUBSCRIBE = 0xa2
const CP_UNSUBACK = 0xb0
const CP_PINGREQ = 0xc0
const CP_PINGRESP = 0xd0
const CP_DISCONNECT = 0xe0

const MAX_PACKET_SIZE = 2097151
const MAX_PACKETS_PER_CLIENT_PER_FRAME = 32

const DEFAULT_FAULT_PROFILE := {
	"enabled": false,
	"seed": 1,
	"topic_filters": [],
	"latency_ms": 0,
	"jitter_ms": 0,
	"loss_rate": 0.0,
	"duplicate_rate": 0.0,
	"reorder_ms": 0,
	"disconnect_after": 0,
}

@export var port := 1883
@export var bind_address := "*"
@export var verbose := true

var _server: TCPServer
var _clients: Array[Dictionary] = []
var _retained: Dictionary = {}
var _fault_profile := DEFAULT_FAULT_PROFILE.duplicate(true)
var _fault_rng := RandomNumberGenerator.new()
var _fault_sequence := 0
var _hold_until_msec := 0
var _fault_counters := {
	"matched": 0,
	"queued": 0,
	"delivered": 0,
	"dropped": 0,
	"duplicated": 0,
	"reordered": 0,
	"interrupted": 0,
}


func configure_faults(options: Dictionary = {}) -> void:
	_fault_profile = DEFAULT_FAULT_PROFILE.duplicate(true)
	for key in options:
		if _fault_profile.has(key):
			_fault_profile[key] = options[key]
	_fault_profile.enabled = bool(_fault_profile.enabled)
	_fault_profile.seed = int(_fault_profile.seed)
	_fault_profile.latency_ms = maxi(0, int(_fault_profile.latency_ms))
	_fault_profile.jitter_ms = maxi(0, int(_fault_profile.jitter_ms))
	_fault_profile.loss_rate = clampf(float(_fault_profile.loss_rate), 0.0, 1.0)
	_fault_profile.duplicate_rate = clampf(float(_fault_profile.duplicate_rate), 0.0, 1.0)
	_fault_profile.reorder_ms = maxi(0, int(_fault_profile.reorder_ms))
	_fault_profile.disconnect_after = maxi(0, int(_fault_profile.disconnect_after))
	_fault_profile.topic_filters = PackedStringArray(_fault_profile.topic_filters)
	_fault_rng.seed = _fault_profile.seed
	_fault_sequence = 0
	_hold_until_msec = 0
	_reset_fault_counters()
	for client in _clients:
		client.outbound_queue.clear()
	_report("Fault profile configured: %s" % JSON.stringify(_fault_profile))


func clear_faults() -> void:
	configure_faults()


func hold_deliveries(duration_ms: int) -> void:
	_hold_until_msec = Time.get_ticks_msec() + maxi(0, duration_ms)
	_report("Holding matching PUBLISH deliveries for %d ms" % maxi(0, duration_ms))


func get_fault_counters() -> Dictionary:
	return _fault_counters.duplicate()


func _reset_fault_counters() -> void:
	for key in _fault_counters:
		_fault_counters[key] = 0


func start(listen_port: int = port) -> int:
	if _server != null:
		return ERR_ALREADY_IN_USE
	_server = TCPServer.new()
	var error := _server.listen(listen_port, bind_address)
	if error != OK:
		_server = null
		_report("Could not listen on %s:%d (error %d)" % [bind_address, listen_port, error])
		return error
	port = listen_port
	set_process(true)
	_report("Simulated MQTT broker listening on %s:%d" % [bind_address, port])
	broker_started.emit(port)
	return OK


func stop() -> void:
	if _server == null:
		return
	for client in _clients.duplicate():
		_remove_client(client, false, false)
	_server.stop()
	_server = null
	set_process(false)
	_report("Simulated MQTT broker stopped")
	broker_stopped.emit()


func is_running() -> bool:
	return _server != null


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_clients.append({
			"peer": peer,
			"buffer": PackedByteArray(),
			"client_id": "",
			"subscriptions": [],
			"will_topic": "",
			"will_payload": PackedByteArray(),
			"will_retain": false,
			"keepalive": 0,
			"last_packet_msec": Time.get_ticks_msec(),
			"outbound_queue": [],
		})

	for client in _clients.duplicate():
		_poll_client(client)

func _poll_client(client: Dictionary) -> void:
	var peer: StreamPeerTCP = client.peer
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_remove_client(client, true)
		return

	var available := peer.get_available_bytes()
	if available > 0:
		var read_result := peer.get_data(available)
		if read_result[0] != OK:
			_remove_client(client, true)
			return
		client.buffer.append_array(read_result[1])

	var packets_processed := 0
	while packets_processed < MAX_PACKETS_PER_CLIENT_PER_FRAME:
		var packet := _take_packet(client)
		if packet.is_empty():
			break
		client.last_packet_msec = Time.get_ticks_msec()
		packets_processed += 1
		if not _handle_packet(client, packet):
			return

	var keepalive: int = client.keepalive
	if keepalive > 0 and Time.get_ticks_msec() - client.last_packet_msec > keepalive * 1500:
		_report("Client %s timed out" % _client_name(client))
		_remove_client(client, true)
		return
	_flush_outbound(client)


func _take_packet(client: Dictionary) -> PackedByteArray:
	var buffer: PackedByteArray = client.buffer
	if buffer.size() < 2:
		return PackedByteArray()
	var index := 1
	var remaining_length := 0
	var multiplier := 1
	var length_bytes := 0
	while true:
		if index == buffer.size():
			return PackedByteArray()
		var encoded_byte := buffer[index]
		index += 1
		length_bytes += 1
		remaining_length += (encoded_byte & 0x7f) * multiplier
		if (encoded_byte & 0x80) == 0:
			break
		if length_bytes == 4:
			_protocol_error(client, "remaining length exceeds four bytes")
			return PackedByteArray()
		multiplier *= 128
	if remaining_length > MAX_PACKET_SIZE:
		_protocol_error(client, "packet exceeds size limit")
		return PackedByteArray()
	var packet_size := index + remaining_length
	if buffer.size() < packet_size:
		return PackedByteArray()
	var packet := buffer.slice(0, packet_size)
	client.buffer = buffer.slice(packet_size)
	return packet


func _handle_packet(client: Dictionary, packet: PackedByteArray) -> bool:
	var header := packet[0]
	var body_offset := _body_offset(packet)
	if body_offset < 0:
		return _protocol_error(client, "invalid remaining length")
	if client.client_id.is_empty() and header != CP_CONNECT:
		return _protocol_error(client, "CONNECT must be the first packet")

	match header & 0xf0:
		CP_CONNECT:
			return _handle_connect(client, packet, body_offset)
		CP_PUBLISH:
			return _handle_publish(client, packet, body_offset)
		CP_SUBSCRIBE & 0xf0:
			return _handle_subscribe(client, packet, body_offset)
		CP_UNSUBSCRIBE & 0xf0:
			return _handle_unsubscribe(client, packet, body_offset)
		CP_PINGREQ:
			_send(client, PackedByteArray([CP_PINGRESP, 0x00]))
			return true
		CP_DISCONNECT:
			_remove_client(client, false)
			return false
		_:
			return _protocol_error(client, "unsupported control packet 0x%02x" % header)


func _handle_connect(client: Dictionary, packet: PackedByteArray, offset: int) -> bool:
	if not client.client_id.is_empty():
		return _protocol_error(client, "second CONNECT packet")
	var cursor := [offset]
	var protocol_name := _read_utf8(packet, cursor)
	if protocol_name != "MQTT" or not _has(packet, cursor[0], 4):
		_send(client, PackedByteArray([CP_CONNACK, 0x02, 0x00, 0x01]))
		_remove_client(client, false)
		return false
	var protocol_level := packet[cursor[0]]
	var flags := packet[cursor[0] + 1]
	var keepalive := _read_u16(packet, cursor[0] + 2)
	cursor[0] += 4
	if protocol_level != 4 or (flags & 0x01) != 0:
		_send(client, PackedByteArray([CP_CONNACK, 0x02, 0x00, 0x01]))
		_remove_client(client, false)
		return false
	var client_id := _read_utf8(packet, cursor)
	if client_id.is_empty():
		client_id = "mosq-%05d" % randi_range(10000,99999) # supposed to be set on v3.1 from mosquitto, but isn't https://mosquitto.org/man/mosquitto_sub-1.html
		_report("Empty client id given: %s" % client_id)
		#return _protocol_error(client, "empty client identifier")
	if flags & 0x04:
		var will_topic := _read_utf8(packet, cursor)
		var will_payload := _read_bytes(packet, cursor)
		if will_topic.is_empty() or will_payload == null:
			return _protocol_error(client, "invalid last will")
		client.will_topic = will_topic
		client.will_payload = will_payload
		client.will_retain = (flags & 0x20) != 0
	if flags & 0x80:
		if _read_bytes(packet, cursor) == null:
			return _protocol_error(client, "invalid username")
	if flags & 0x40:
		if _read_bytes(packet, cursor) == null:
			return _protocol_error(client, "invalid password")
	for existing in _clients.duplicate():
		if existing != client and existing.client_id == client_id:
			_remove_client(existing, true)
	client.client_id = client_id
	client.keepalive = keepalive
	_send(client, PackedByteArray([CP_CONNACK, 0x02, 0x00, 0x00]))
	_report("Client connected: %s" % client_id)
	client_connected.emit(client_id)
	return true


func _handle_subscribe(client: Dictionary, packet: PackedByteArray, offset: int) -> bool:
	if (packet[0] & 0x0f) != 0x02 or not _has(packet, offset, 2):
		return _protocol_error(client, "invalid SUBSCRIBE")
	var packet_id := _read_u16(packet, offset)
	var cursor := [offset + 2]
	var granted := PackedByteArray()
	while cursor[0] < packet.size():
		var topic_filter := _read_utf8(packet, cursor)
		if topic_filter.is_empty() or not _has(packet, cursor[0], 1):
			return _protocol_error(client, "invalid subscription filter")
		cursor[0] += 1
		if not topic_filter in client.subscriptions:
			client.subscriptions.append(topic_filter)
		granted.append(0)
		for retained_topic in _retained:
			if _topic_matches(topic_filter, retained_topic):
				_send_publish(client, retained_topic, _retained[retained_topic], true)
	var response := PackedByteArray([CP_SUBACK, 2 + granted.size()])
	_append_u16(response, packet_id)
	response.append_array(granted)
	_send(client, response)
	return true


func _handle_unsubscribe(client: Dictionary, packet: PackedByteArray, offset: int) -> bool:
	if (packet[0] & 0x0f) != 0x02 or not _has(packet, offset, 2):
		return _protocol_error(client, "invalid UNSUBSCRIBE")
	var packet_id := _read_u16(packet, offset)
	var cursor := [offset + 2]
	while cursor[0] < packet.size():
		var topic_filter := _read_utf8(packet, cursor)
		client.subscriptions.erase(topic_filter)
	var response := PackedByteArray([CP_UNSUBACK, 0x02])
	_append_u16(response, packet_id)
	_send(client, response)
	return true


func _handle_publish(client: Dictionary, packet: PackedByteArray, offset: int) -> bool:
	var qos := (packet[0] >> 1) & 0x03
	if qos > 1:
		return _protocol_error(client, "QoS 2 is not supported")
	var cursor := [offset]
	var topic := _read_utf8(packet, cursor)
	if topic.is_empty():
		return _protocol_error(client, "invalid publish topic")
	var packet_id := 0
	if qos == 1:
		if not _has(packet, cursor[0], 2):
			return _protocol_error(client, "missing publish packet identifier")
		packet_id = _read_u16(packet, cursor[0])
		cursor[0] += 2
	var payload := packet.slice(cursor[0])
	_publish(topic, payload, (packet[0] & 0x01) != 0)
	if qos == 1:
		var response := PackedByteArray([CP_PUBACK, 0x02])
		_append_u16(response, packet_id)
		_send(client, response)
	return true


func _publish(topic: String, payload: PackedByteArray, retain: bool) -> void:
	if retain:
		if payload.is_empty():
			_retained.erase(topic)
		else:
			_retained[topic] = payload
	for client in _clients:
		if client.client_id.is_empty():
			continue
		for topic_filter in client.subscriptions:
			if _topic_matches(topic_filter, topic):
				_send_publish(client, topic, payload, false)
				break


func _send_publish(client: Dictionary, topic: String, payload: PackedByteArray, retain: bool) -> void:
	var body := PackedByteArray()
	_append_utf8(body, topic)
	body.append_array(payload)
	var packet := PackedByteArray([CP_PUBLISH | (0x01 if retain else 0)])
	_append_remaining_length(packet, body.size())
	packet.append_array(body)
	_send_application_publish(client, topic, packet)


func _send_application_publish(client: Dictionary, topic: String, packet: PackedByteArray) -> void:
	if not _fault_matches(topic):
		_send(client, packet)
		return
	_fault_counters.matched += 1
	var disconnect_after: int = _fault_profile.disconnect_after
	if disconnect_after > 0 and _fault_counters.matched == disconnect_after:
		_fault_counters.interrupted += 1
		_report("Fault interrupted %s after matched delivery %d" % [_client_name(client), disconnect_after])
		_remove_client(client, true)
		return
	if _fault_rng.randf() < float(_fault_profile.loss_rate):
		_fault_counters.dropped += 1
		_report("Fault dropped PUBLISH topic=%s sequence=%d" % [topic, _fault_sequence])
		_fault_sequence += 1
		return
	_queue_fault_delivery(client, topic, packet)
	if _fault_rng.randf() < float(_fault_profile.duplicate_rate):
		_fault_counters.duplicated += 1
		_queue_fault_delivery(client, topic, packet)


func _fault_matches(topic: String) -> bool:
	if not _fault_profile.enabled:
		return false
	var filters: PackedStringArray = _fault_profile.topic_filters
	if filters.is_empty():
		return true
	for topic_filter in filters:
		if _topic_matches(topic_filter, topic):
			return true
	return false


func _queue_fault_delivery(client: Dictionary, topic: String, packet: PackedByteArray) -> void:
	var jitter := 0
	if _fault_profile.jitter_ms > 0:
		jitter = _fault_rng.randi_range(-_fault_profile.jitter_ms, _fault_profile.jitter_ms)
	var reorder_delay := 0
	if _fault_profile.reorder_ms > 0:
		reorder_delay = _fault_rng.randi_range(0, _fault_profile.reorder_ms)
		if reorder_delay > 0:
			_fault_counters.reordered += 1
	var due_msec := Time.get_ticks_msec() + maxi(0, _fault_profile.latency_ms + jitter) + reorder_delay
	client.outbound_queue.append({
		"packet": packet,
		"topic": topic,
		"due_msec": due_msec,
		"sequence": _fault_sequence,
	})
	_fault_sequence += 1
	_fault_counters.queued += 1


func _flush_outbound(client: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now < _hold_until_msec:
		return
	var queue: Array = client.outbound_queue
	queue.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.due_msec == b.due_msec:
			return a.sequence < b.sequence
		return a.due_msec < b.due_msec
	)
	while not queue.is_empty() and int(queue[0].due_msec) <= now:
		var delivery: Dictionary = queue.pop_front()
		if not _send(client, delivery.packet):
			return
		_fault_counters.delivered += 1


func _remove_client(client: Dictionary, unexpected: bool, publish_will: bool = true) -> void:
	if not client in _clients:
		return
	_clients.erase(client)
	var client_id: String = client.client_id
	if unexpected and publish_will and not client.will_topic.is_empty():
		_publish(client.will_topic, client.will_payload, client.will_retain)
	var peer: StreamPeerTCP = client.peer
	peer.disconnect_from_host()
	if not client_id.is_empty():
		_report("Client disconnected: %s%s" % [client_id, " unexpectedly" if unexpected else ""])
		client_disconnected.emit(client_id, unexpected)


func _topic_matches(topic_filter: String, topic: String) -> bool:
	var filter_levels := topic_filter.split("/", true)
	var topic_levels := topic.split("/", true)
	for index in range(filter_levels.size()):
		var filter_level := filter_levels[index]
		if filter_level == "#":
			return index == filter_levels.size() - 1
		if index >= topic_levels.size():
			return false
		if filter_level != "+" and filter_level != topic_levels[index]:
			return false
	return filter_levels.size() == topic_levels.size()


func _body_offset(packet: PackedByteArray) -> int:
	var index := 1
	for count in range(4):
		if index >= packet.size():
			return -1
		var encoded_byte := packet[index]
		index += 1
		if (encoded_byte & 0x80) == 0:
			return index
	return -1


func _read_utf8(packet: PackedByteArray, cursor: Array) -> Variant:
	var bytes := _read_bytes(packet, cursor)
	return null if bytes == null else bytes.get_string_from_utf8()


func _read_bytes(packet: PackedByteArray, cursor: Array) -> Variant:
	if not _has(packet, cursor[0], 2):
		return null
	var size := _read_u16(packet, cursor[0])
	cursor[0] += 2
	if not _has(packet, cursor[0], size):
		return null
	var value := packet.slice(cursor[0], cursor[0] + size)
	cursor[0] += size
	return value


func _has(packet: PackedByteArray, offset: int, size: int) -> bool:
	return offset >= 0 and size >= 0 and offset + size <= packet.size()


func _read_u16(packet: PackedByteArray, offset: int) -> int:
	return (packet[offset] << 8) + packet[offset + 1]


func _append_u16(packet: PackedByteArray, value: int) -> void:
	packet.append((value >> 8) & 0xff)
	packet.append(value & 0xff)


func _append_utf8(packet: PackedByteArray, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	_append_u16(packet, bytes.size())
	packet.append_array(bytes)


func _append_remaining_length(packet: PackedByteArray, value: int) -> void:
	while true:
		var encoded_byte := value % 128
		value /= 128
		if value > 0:
			encoded_byte |= 0x80
		packet.append(encoded_byte)
		if value == 0:
			return


func _send(client: Dictionary, packet: PackedByteArray) -> bool:
	var peer: StreamPeerTCP = client.peer
	var error := peer.put_data(packet)
	if error != OK:
		_remove_client(client, true)
		return false
	return true


func _protocol_error(client: Dictionary, message: String) -> bool:
	_report("Protocol error from %s: %s" % [_client_name(client), message])
	_remove_client(client, true)
	return false


func _client_name(client: Dictionary) -> String:
	return client.client_id if not client.client_id.is_empty() else "unidentified client"


func _report(message: String) -> void:
	if verbose:
		print(message)
	diagnostic.emit(message)
