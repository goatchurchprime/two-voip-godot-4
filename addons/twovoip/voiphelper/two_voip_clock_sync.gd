class_name TwoVoipClockSync
extends Node

signal transmit_packet(packet: PackedByteArray, recipient: String)
signal estimate_changed(peer_id: String, estimate: Dictionary)
signal synchronization_finished(success: bool, missing_peers: Array[String])

const PROBE_COUNT := 4
const PROBE_LIMIT := 20
const PROBE_INTERVAL_SECONDS := 0.05

var local_peer_id := ""
var connection_generation := 0
var probe_sequence := 0
var transport_is_ready := false
var pending_probes := {}
var sent_responses := {}
var estimates := {}
var peer_speakers := {}


# t1/t4 use the initiating clock; t2/t3 use the responding clock.
# The returned interval contains responder-minus-initiator without assuming
# equal one-way delays. The midpoint is only the best symmetric-path guess.
static func calculate_exchange(t1_usec: int, t2_usec: int,
		t3_usec: int, t4_usec: int) -> Dictionary:
	if t3_usec < t2_usec or t4_usec < t1_usec:
		return {}
	var offset_lower_usec := t3_usec - t4_usec
	var offset_upper_usec := t2_usec - t1_usec
	if offset_upper_usec < offset_lower_usec:
		return {}
	var round_trip_usec := offset_upper_usec - offset_lower_usec
	return {
		"remote_minus_local_usec": roundi((offset_lower_usec + offset_upper_usec) / 2.0),
		"offset_lower_usec": offset_lower_usec,
		"offset_upper_usec": offset_upper_usec,
		"uncertainty_usec": ceili(round_trip_usec / 2.0),
		"round_trip_usec": round_trip_usec,
	}


func _now_usec() -> int:
	return Time.get_ticks_usec()


func _unix_minus_ticks_usec(ticks_usec: int) -> int:
	return int(Time.get_unix_time_from_system() * 1000000.0) - ticks_usec


func register_peer(peer_id: String, speaker: Node):
	peer_speakers[peer_id] = speaker
	_apply_estimate(peer_id)


func unregister_peer(peer_id: String):
	peer_speakers.erase(peer_id)
	estimates.erase(peer_id)


func transport_connected(peer_id: String):
	connection_generation += 1
	local_peer_id = peer_id
	transport_is_ready = true
	pending_probes.clear()
	sent_responses.clear()
	estimates.clear()
	_synchronize(connection_generation)


func transport_disconnected():
	connection_generation += 1
	transport_is_ready = false
	pending_probes.clear()
	sent_responses.clear()
	estimates.clear()
	peer_speakers.clear()


func has_estimate(peer_id: String) -> bool:
	return estimates.has(peer_id)


func get_estimate(peer_id: String) -> Dictionary:
	return estimates.get(peer_id, {})


func _apply_estimate(peer_id: String):
	if not estimates.has(peer_id) or not peer_speakers.has(peer_id):
		return
	var speaker: Node = peer_speakers[peer_id]
	if not is_instance_valid(speaker):
		peer_speakers.erase(peer_id)
		return
	var estimate: Dictionary = estimates[peer_id]
	speaker.set_source_clock_estimate(
			int(estimate.local_minus_peer_usec), int(estimate.lower_bound_usec),
			int(estimate.upper_bound_usec), int(estimate.round_trip_usec),
			str(estimate.reason), int(estimate.get("unix_local_minus_peer_usec", 0)),
			bool(estimate.get("unix_offset_valid", false)))


func _store_estimate(peer_id: String, estimate_usec: int, lower_bound_usec: int,
		upper_bound_usec: int, round_trip_usec: int, reason: String, probe_id: String,
		unix_local_minus_peer_usec: int = 0, unix_offset_valid := false,
		force_selection := false) -> bool:
	if not force_selection and estimates.has(peer_id) \
			and int(estimates[peer_id].round_trip_usec) <= round_trip_usec:
		return false
	var estimate := {
		"local_minus_peer_usec": estimate_usec,
		"lower_bound_usec": lower_bound_usec,
		"upper_bound_usec": upper_bound_usec,
		"round_trip_usec": round_trip_usec,
		"reason": reason,
		"probe_id": probe_id,
		"unix_local_minus_peer_usec": unix_local_minus_peer_usec,
		"unix_offset_valid": unix_offset_valid,
	}
	estimates[peer_id] = estimate
	_apply_estimate(peer_id)
	estimate_changed.emit(peer_id, estimate)
	var unix_diagnostic := ""
	if unix_offset_valid:
		unix_diagnostic = " unix=%+.3f ms selected-unix=%+.3f ms" % [
				unix_local_minus_peer_usec / 1000.0,
				(estimate_usec - unix_local_minus_peer_usec) / 1000.0]
	print("TwoVoIP clock %s local-peer=%+.3f ms bounds=[%+.3f,%+.3f] ms RTT=%.3f ms%s (%s)" % [
			peer_id, estimate_usec / 1000.0, lower_bound_usec / 1000.0,
			upper_bound_usec / 1000.0, round_trip_usec / 1000.0,
			unix_diagnostic, reason])
	return true


func _send_probe():
	probe_sequence += 1
	var probe_id := "%s:%d" % [local_peer_id, probe_sequence]
	var t1_usec := _now_usec()
	var unix_minus_ticks_usec := _unix_minus_ticks_usec(t1_usec)
	pending_probes[probe_id] = {"t1_usec": t1_usec, "unix_minus_ticks_usec": unix_minus_ticks_usec}
	transmit_packet.emit(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_clock_ping(
			probe_id, t1_usec, "", unix_minus_ticks_usec)), "")


func _all_registered_peers_synced() -> bool:
	for peer_id in peer_speakers:
		if is_instance_valid(peer_speakers[peer_id]) and not estimates.has(peer_id):
			return false
	return true


func _synchronize(generation: int):
	var probes_sent := 0
	while probes_sent < PROBE_COUNT \
			or (not _all_registered_peers_synced() and probes_sent < PROBE_LIMIT):
		if generation != connection_generation or not transport_is_ready:
			return
		_send_probe()
		probes_sent += 1
		await get_tree().create_timer(PROBE_INTERVAL_SECONDS).timeout
	if generation != connection_generation or not transport_is_ready:
		return
	var missing_peers: Array[String] = []
	for peer_id in peer_speakers:
		if is_instance_valid(peer_speakers[peer_id]) and not estimates.has(peer_id):
			missing_peers.append(peer_id)
	pending_probes.clear()
	synchronization_finished.emit(missing_peers.is_empty(), missing_peers)


func receive_packet(peer_id: String, wire_packet: PackedByteArray,
		arrival_time_usec: int = 0, replay := false) -> bool:
	var packet := TwoVoipPacket.decode_control_packet(wire_packet)
	if packet.is_empty():
		return false
	var arrival_usec := arrival_time_usec if arrival_time_usec > 0 else _now_usec()
	if TwoVoipPacket.clock_ping_is_valid(packet):
		if replay:
			return true
		var probe_id: String = packet[TwoVoipPacket.ClockPingField.PROBE_ID]
		var t1_usec := int(packet[TwoVoipPacket.ClockPingField.T1_USEC])
		var t2_usec := arrival_usec
		var t3_usec := _now_usec()
		var local_unix_minus_ticks_usec := _unix_minus_ticks_usec(t3_usec)
		sent_responses[probe_id] = {
			"peer_id": peer_id, "t1_usec": t1_usec, "t2_usec": t2_usec,
			"t3_usec": t3_usec, "local_unix_minus_ticks_usec": local_unix_minus_ticks_usec,
		}
		transmit_packet.emit(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_clock_pong(
				probe_id, t1_usec, t2_usec, t3_usec, "", local_unix_minus_ticks_usec)), peer_id)
		return true
	if TwoVoipPacket.clock_pong_is_valid(packet):
		var probe_id: String = packet[TwoVoipPacket.ClockPongField.PROBE_ID]
		var t1_usec := int(packet[TwoVoipPacket.ClockPongField.T1_USEC])
		if not replay and (not pending_probes.has(probe_id) \
				or int(pending_probes[probe_id].t1_usec) != t1_usec):
			return true
		var t2_usec := int(packet[TwoVoipPacket.ClockPongField.T2_USEC])
		var t3_usec := int(packet[TwoVoipPacket.ClockPongField.T3_USEC])
		var result := calculate_exchange(t1_usec, t2_usec, t3_usec, arrival_usec)
		var local_unix_minus_ticks_usec := int(pending_probes[probe_id].unix_minus_ticks_usec) \
				if pending_probes.has(probe_id) else 0
		var peer_unix_minus_ticks_usec := TwoVoipPacket.clock_pong_unix_minus_ticks_usec(packet)
		var unix_offset_valid := local_unix_minus_ticks_usec != 0 and peer_unix_minus_ticks_usec != 0
		var unix_local_minus_peer_usec := peer_unix_minus_ticks_usec - local_unix_minus_ticks_usec
		var selected_estimate := false
		if not result.is_empty():
			selected_estimate = _store_estimate(peer_id, -int(result.remote_minus_local_usec),
					-int(result.offset_upper_usec), -int(result.offset_lower_usec),
					int(result.round_trip_usec), "connection clock pong", probe_id,
					unix_local_minus_peer_usec, unix_offset_valid)
		if not replay:
			transmit_packet.emit(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_clock_ack(
					probe_id, t1_usec, t2_usec, t3_usec, arrival_usec,
					local_unix_minus_ticks_usec, selected_estimate)), peer_id)
		return true
	if TwoVoipPacket.clock_ack_is_valid(packet):
		var probe_id: String = packet[TwoVoipPacket.ClockAckField.PROBE_ID]
		if not sent_responses.has(probe_id):
			return true
		var sent: Dictionary = sent_responses[probe_id]
		var t1_usec := int(packet[TwoVoipPacket.ClockAckField.T1_USEC])
		var t2_usec := int(packet[TwoVoipPacket.ClockAckField.T2_USEC])
		var t3_usec := int(packet[TwoVoipPacket.ClockAckField.T3_USEC])
		var t4_usec := int(packet[TwoVoipPacket.ClockAckField.T4_USEC])
		if sent.peer_id == peer_id and int(sent.t1_usec) == t1_usec \
				and int(sent.t2_usec) == t2_usec and int(sent.t3_usec) == t3_usec:
			var result := calculate_exchange(t1_usec, t2_usec, t3_usec, t4_usec)
			var peer_unix_minus_ticks_usec := TwoVoipPacket.clock_ack_unix_minus_ticks_usec(packet)
			var local_unix_minus_ticks_usec := int(sent.local_unix_minus_ticks_usec)
			var unix_offset_valid := peer_unix_minus_ticks_usec != 0 and local_unix_minus_ticks_usec != 0
			var unix_local_minus_peer_usec := peer_unix_minus_ticks_usec - local_unix_minus_ticks_usec
			if not result.is_empty() and TwoVoipPacket.clock_ack_applies_estimate(packet):
				_store_estimate(peer_id, int(result.remote_minus_local_usec),
						int(result.offset_lower_usec), int(result.offset_upper_usec),
						int(result.round_trip_usec), "connection clock acknowledgement", probe_id,
						unix_local_minus_peer_usec, unix_offset_valid, true)
		sent_responses.erase(probe_id)
		return true
	return false
