extends Node

# Demo-only packet faults applied at the single boundary immediately before a
# received MQTT audio packet enters TwoVoipSpeaker.

const KIND_AUDIO := "audio"
const KIND_START := "start"
const KIND_MID := "mid"
const KIND_END := "end"

var delayed_kind := ""
var delay_chance := 0.0
var delay_min_ms := 0
var delay_max_ms := 0

var forwarded_count := 0
var dropped_count := 0
var delayed_count := 0

var _drop_kind := ""
var _drop_remaining := 0
var _drop_member_id := 0
var _delay_rng := RandomNumberGenerator.new()


func set_random_delay(enabled: bool, packet_kind: String = KIND_AUDIO,
		seed: int = 7, chance: float = 0.35,
		minimum_ms: int = 30, maximum_ms: int = 160) -> void:
	delayed_kind = packet_kind if enabled else ""
	delay_chance = clampf(chance, 0.0, 1.0)
	delay_min_ms = maxi(0, mini(minimum_ms, maximum_ms))
	delay_max_ms = maxi(delay_min_ms, maximum_ms)
	_delay_rng.seed = seed


func drop_next(packet_kind: String, count: int = 1) -> void:
	_drop_kind = packet_kind
	_drop_remaining = maxi(0, count)
	_drop_member_id = 0


func receive_audio_packet(member: Object, packet,
		transport_debug_context: Dictionary = {}) -> void:
	if not is_instance_valid(member):
		return
	var member_id := member.get_instance_id()
	var packet_kind := _packet_kind(packet)
	if _drop_remaining > 0 and packet_kind == _drop_kind \
			and (_drop_member_id == 0 or _drop_member_id == member_id):
		_drop_member_id = member_id
		_drop_remaining -= 1
		dropped_count += 1
		if _drop_remaining == 0:
			_drop_kind = ""
			_drop_member_id = 0
		return

	var received := {
		"member": member,
		"packet": packet,
		"context": transport_debug_context,
	}
	if packet_kind != delayed_kind or _delay_rng.randf() >= delay_chance:
		_deliver(received)
		return

	var delay_ms := _delay_rng.randi_range(delay_min_ms, delay_max_ms)
	received["delay_ms"] = delay_ms
	delayed_count += 1
	await get_tree().create_timer(delay_ms / 1000.0).timeout
	_deliver(received)


func _packet_kind(packet) -> String:
	if not packet is PackedByteArray or not TwoVoipPacket.is_control_packet(packet):
		return KIND_AUDIO
	var control_packet := TwoVoipPacket.decode_control_packet(packet)
	if control_packet.is_empty():
		return "control"
	var packet_type := str(control_packet[0])
	return packet_type if packet_type in [KIND_START, KIND_MID, KIND_END] \
			else "control"


func _deliver(received: Dictionary) -> void:
	var member: Object = received.member
	if not is_instance_valid(member):
		return
	var context: Dictionary = received.context.duplicate(true)
	if received.has("delay_ms"):
		context["fault_input_arrival_time_usec"] = context.get(
				"arrival_time_usec", 0)
		context["fault_delay_ms"] = received.delay_ms
		context["arrival_time_usec"] = Time.get_ticks_usec()
		context["arrival_ticks_msec"] = Time.get_ticks_msec()
	forwarded_count += 1
	member.receive_mqtt_audio_packet(received.packet, context)
