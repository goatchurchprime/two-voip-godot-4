extends Control

const ClockSync = preload("res://addons/twovoip/voiphelper/two_voip_clock_sync.gd")
const CLOCK_PROBE_COUNT := 4
const CLOCK_PROBE_LIMIT := 20
const CLOCK_PROBE_INTERVAL_SECONDS := 0.05

var myname = ""
var roomtopic = ""
var roomtopicwords = 0
var audioouttopic = "" 
var audioouttopicmeta = "" 
var audiodirectintopicmeta = ""
var statustopic = ""

@onready var Members = get_node("../ScrollMembers/Members")
@onready var SelfMember = get_node("../ScrollMembers/Members/Self")

@onready var Mstatusconnected = "connected".to_ascii_buffer()
@onready var Mstatusconnecting = "connecting".to_ascii_buffer()
@onready var Mstatusdisconnected = "disconnnected".to_ascii_buffer()
@onready var MstatusdisconnectedLW = "disconnected-LW".to_ascii_buffer()

var pending_ready_subscriptions := {}
var pending_mid_recipients := {}
var network_ready := false
var network_ready_failed := false
var connection_announced := false
var clock_connection_generation := 0
var clock_probe_sequence := 0
var pending_clock_probes := {}
var sent_clock_responses := {}
var clock_estimates := {}
var clock_domain_id := ""

const logfile = "user://mqttlogging.dat"
var flogfile : FileAccess = null
var logfilepackcount = 0
var recording_start_ticks_msec = 0
var recording_start_unix_usec = 0
var replay_recording_key := ""
var replay_arrival_epoch_usec := 0

func encode_log_payload(msg: PackedByteArray) -> String:
	return "b64:%s" % Marshalls.raw_to_base64(msg)

func decode_log_payload(encoded: String) -> PackedByteArray:
	if encoded.begins_with("b64:"):
		return Marshalls.base64_to_raw(encoded.substr(4))
	return encoded.to_ascii_buffer()

func send_midstream_start(membername: String):
	for midpacket in get_node("../TwoVoipMic").request_audio_packet_midstream():
		transportaudiopacket(midpacket, 0, membername)


func _now_usec() -> int:
	return int(Time.get_unix_time_from_system() * 1000000.0)


func _get_clock_domain_id() -> String:
	if clock_domain_id.is_empty() and OS.has_method("get_unique_id"):
		var unique_id := str(OS.call("get_unique_id"))
		if not unique_id.is_empty():
			clock_domain_id = ("twovoip-clock-domain:" + unique_id).sha256_text()
	return clock_domain_id


func _ensure_member(membername: String):
	var member = Members.get_node_or_null(membername)
	if member == null:
		member = load("res://radiomqtt/member.tscn").instantiate()
		member.setname(membername)
		Members.add_child(member)
		member.get_node("AudioStreamPlayer/TwoVoipSpeaker").hash_response_ready.connect(
				func(packet): transportaudiopacket(packet, 0, membername))
	_apply_clock_estimate(membername)
	return member


func _apply_clock_estimate(membername: String):
	if not clock_estimates.has(membername):
		return
	var member = Members.get_node_or_null(membername)
	if member == null:
		return
	var estimate: Dictionary = clock_estimates[membername]
	member.get_node("AudioStreamPlayer/TwoVoipSpeaker").set_source_clock_estimate(
			int(estimate.local_minus_peer_usec),
			int(estimate.lower_bound_usec),
			int(estimate.upper_bound_usec),
			int(estimate.round_trip_usec),
			str(estimate.reason))


func _store_clock_estimate(membername: String, estimate_usec: int,
		lower_bound_usec: int, upper_bound_usec: int, round_trip_usec: int,
		reason: String, probe_id: String):
	if clock_estimates.has(membername) \
			and int(clock_estimates[membername].round_trip_usec) <= round_trip_usec:
		return
	clock_estimates[membername] = {
		"local_minus_peer_usec": estimate_usec,
		"lower_bound_usec": lower_bound_usec,
		"upper_bound_usec": upper_bound_usec,
		"round_trip_usec": round_trip_usec,
		"reason": reason,
		"probe_id": probe_id,
	}
	_apply_clock_estimate(membername)
	print("TwoVoIP clock %s local-peer=%+.3f ms bounds=[%+.3f,%+.3f] ms RTT=%.3f ms (%s)" % [
			membername, estimate_usec / 1000.0,
			lower_bound_usec / 1000.0, upper_bound_usec / 1000.0,
			round_trip_usec / 1000.0, reason])


func _send_clock_probe():
	clock_probe_sequence += 1
	var probe_id := "%s:%d" % [myname, clock_probe_sequence]
	var t1_usec := _now_usec()
	pending_clock_probes[probe_id] = t1_usec
	transportaudiopacket(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_clock_ping(
					probe_id, t1_usec, _get_clock_domain_id())), 0)


func _all_known_peers_clock_synced() -> bool:
	for membername in pending_mid_recipients:
		if not clock_estimates.has(membername):
			return false
	return true


func _clock_sync_before_connected(generation: int):
	var probes_sent := 0
	while probes_sent < CLOCK_PROBE_COUNT \
			or (not _all_known_peers_clock_synced() \
			and probes_sent < CLOCK_PROBE_LIMIT):
		if generation != clock_connection_generation or not network_ready:
			return
		_send_clock_probe()
		probes_sent += 1
		await get_tree().create_timer(CLOCK_PROBE_INTERVAL_SECONDS).timeout
	if generation != clock_connection_generation or not network_ready:
		return
	if not _all_known_peers_clock_synced():
		var missing_peers: Array[String] = []
		for membername in pending_mid_recipients:
			if not clock_estimates.has(membername):
				missing_peers.append(membername)
		push_error("TwoVoIP remains connecting: no clock pong from %s" \
				% ", ".join(missing_peers))
		return
	pending_clock_probes.clear()
	connection_announced = true
	$MQTT.publish(statustopic, Mstatusconnected, true)
	$Connect/ColorRectConnecting.visible = false
	for membername in pending_mid_recipients:
		send_midstream_start(membername)
	pending_mid_recipients.clear()


func _handle_clock_control(membername: String, packet: Array,
		arrival_time_usec: int, replay: bool) -> bool:
	if TwoVoipPacket.clock_ping_is_valid(packet):
		if replay:
			return true
		var probe_id: String = packet[TwoVoipPacket.ClockPingField.PROBE_ID]
		var t1_usec := int(packet[TwoVoipPacket.ClockPingField.T1_USEC])
		var peer_clock_domain_id := TwoVoipPacket.clock_ping_domain_id(packet)
		var t2_usec := arrival_time_usec
		var t3_usec := _now_usec()
		sent_clock_responses[probe_id] = {
			"membername": membername,
			"t1_usec": t1_usec,
			"t2_usec": t2_usec,
			"t3_usec": t3_usec,
			"shared_clock_domain": not peer_clock_domain_id.is_empty() \
					and peer_clock_domain_id == _get_clock_domain_id(),
		}
		transportaudiopacket(TwoVoipPacket.encode_control_packet(
				TwoVoipPacket.make_clock_pong(
						probe_id, t1_usec, t2_usec, t3_usec,
						_get_clock_domain_id())), 0, membername)
		return true
	if TwoVoipPacket.clock_pong_is_valid(packet):
		var probe_id: String = packet[TwoVoipPacket.ClockPongField.PROBE_ID]
		var t1_usec := int(packet[TwoVoipPacket.ClockPongField.T1_USEC])
		if not replay and (not pending_clock_probes.has(probe_id) \
				or int(pending_clock_probes[probe_id]) != t1_usec):
			return true
		var t2_usec := int(packet[TwoVoipPacket.ClockPongField.T2_USEC])
		var t3_usec := int(packet[TwoVoipPacket.ClockPongField.T3_USEC])
		var peer_clock_domain_id := TwoVoipPacket.clock_pong_domain_id(packet)
		var t4_usec := arrival_time_usec
		var result: Dictionary = ClockSync.calculate_exchange(
				t1_usec, t2_usec, t3_usec, t4_usec)
		if not result.is_empty():
			if not peer_clock_domain_id.is_empty() \
					and peer_clock_domain_id == _get_clock_domain_id():
				_store_clock_estimate(membername, 0, 0, 0,
						int(result.round_trip_usec),
						"shared system clock", probe_id)
			else:
				# The result is peer-minus-local; speakers need local-minus-source.
				_store_clock_estimate(membername,
						-int(result.remote_minus_local_usec),
						-int(result.offset_upper_usec),
						-int(result.offset_lower_usec),
						int(result.round_trip_usec),
						"connection clock pong", probe_id)
		if not replay:
			transportaudiopacket(TwoVoipPacket.encode_control_packet(
					TwoVoipPacket.make_clock_ack(
							probe_id, t1_usec, t2_usec, t3_usec, t4_usec)),
					0, membername)
		return true
	if TwoVoipPacket.clock_ack_is_valid(packet):
		var probe_id: String = packet[TwoVoipPacket.ClockAckField.PROBE_ID]
		if not sent_clock_responses.has(probe_id):
			return true
		var sent: Dictionary = sent_clock_responses[probe_id]
		var t1_usec := int(packet[TwoVoipPacket.ClockAckField.T1_USEC])
		var t2_usec := int(packet[TwoVoipPacket.ClockAckField.T2_USEC])
		var t3_usec := int(packet[TwoVoipPacket.ClockAckField.T3_USEC])
		var t4_usec := int(packet[TwoVoipPacket.ClockAckField.T4_USEC])
		if sent.membername == membername and int(sent.t1_usec) == t1_usec \
				and int(sent.t2_usec) == t2_usec and int(sent.t3_usec) == t3_usec:
			var result: Dictionary = ClockSync.calculate_exchange(
					t1_usec, t2_usec, t3_usec, t4_usec)
			if not result.is_empty():
				if bool(sent.shared_clock_domain):
					_store_clock_estimate(membername, 0, 0, 0,
							int(result.round_trip_usec),
							"shared system clock", probe_id)
				else:
					_store_clock_estimate(membername,
							int(result.remote_minus_local_usec),
							int(result.offset_lower_usec),
							int(result.offset_upper_usec),
							int(result.round_trip_usec),
							"connection clock acknowledgement", probe_id)
		sent_clock_responses.erase(probe_id)
		return true
	return false

func subscribe_ready_channel(topic_filter: String):
	var packet_id: int = $MQTT.subscribe(topic_filter)
	pending_ready_subscriptions[packet_id] = topic_filter

func on_subscribe_acknowledge(packet_id: int, result: int):
	if not pending_ready_subscriptions.has(packet_id):
		return
	var topic_filter: String = pending_ready_subscriptions[packet_id]
	pending_ready_subscriptions.erase(packet_id)
	if result == 0x80:
		network_ready_failed = true
		push_error("MQTT relay subscription rejected: %s" % topic_filter)
	if not pending_ready_subscriptions.is_empty():
		return
	if network_ready_failed:
		return
	network_ready = true
	audioouttopic = "%s/%s/audio" % [roomtopic, myname]
	audioouttopicmeta = "%s/%s/audio/meta" % [roomtopic, myname]
	_clock_sync_before_connected(clock_connection_generation)

func _ready():
	if $GridContainer/presets.selected == -1:
		$GridContainer/presets.select(0)
	_on_mqtt_broker_item_selected($GridContainer/presets.selected)

func _on_mqtt_broker_item_selected(index):
	var preset = $GridContainer/presets.text
	$GridContainer/mqttuser.text = ""
	$GridContainer/mqttpassword.text = ""
	$GridContainer/topic.text = "godot/twovoip/room1"
	if preset == "local" or preset == "local.broker":
		$GridContainer/broker.text = "127.0.0.1"
	elif preset == "hivemq":
		$GridContainer/broker.text = "broker.hivemq.com"
	elif preset == "m.org":
		$GridContainer/broker.text = "test.mosquitto.org"
	elif preset == "hass":
		$GridContainer/broker.text = "homeassistant.local"
		$GridContainer/mqttuser.text = "mqttuser"
		$GridContainer/mqttpassword.text = "mqttpwd"
	else:
		$GridContainer/broker.text = "mosquitto.doesliverpool.xyz"
	#if OS.has_feature("web"):
	#	$GridContainer/broker.text = "test.mosquitto.org"

	if preset == "local.broker":
		$MQTTSimulatedBroker.start()
	elif $MQTTSimulatedBroker._server:
		$MQTTSimulatedBroker.stop()

func transportaudiopacket(packet: PackedByteArray, dithertype: int, meta_recipient := ""):
	var topic = audioouttopicmeta if TwoVoipPacket.is_control_packet(packet) else audioouttopic
	if topic.is_empty():
		return
	if not meta_recipient.is_empty():
		assert(TwoVoipPacket.is_control_packet(packet))
		topic += "/%s" % meta_recipient
	if dithertype and randf() < 0.2:
		var tt = abs(randfn(0.0, 0.1))
		print("Delaying dither ", tt)
		await get_tree().create_timer(tt).timeout
	$MQTT.publish(topic, packet)


func received_mqtt(topic, msg, transport_debug_context: Dictionary = {}):
	var arrival_ticks_msec := Time.get_ticks_msec()
	var packet_context := transport_debug_context.duplicate(true)
	var arrival_time_usec := int(packet_context.get("arrival_time_usec", _now_usec()))
	packet_context["arrival_ticks_msec"] = arrival_ticks_msec
	packet_context["arrival_time_usec"] = arrival_time_usec
	packet_context["topic"] = topic
	if flogfile != null:
		# Base64 keeps arbitrary binary Opus/control payloads byte-exact. Replay
		# still accepts the former plain-ASCII third field for existing logs.
		flogfile.store_line("%d %s %s" % [arrival_ticks_msec, topic,
				encode_log_payload(msg)])
		logfilepackcount += 1
		packet_context["record_packet_index"] = logfilepackcount
		packet_context["recording_start_ticks_msec"] = recording_start_ticks_msec
		get_node("../HBoxLogging/PacketCount").text = str(logfilepackcount)
	var stopic = topic.split("/", true, roomtopicwords+1)
	if len(stopic) == roomtopicwords + 2:
		var membername = stopic[roomtopicwords]
		if stopic[roomtopicwords+1] == "status":
			if membername != myname:
				if msg == Mstatusconnected:
					_ensure_member(membername)
					if connection_announced:
						send_midstream_start(membername)
					else:
						pending_mid_recipients[membername] = true
				elif msg == Mstatusconnecting:
					pass
					
				elif msg == Mstatusdisconnected or msg == MstatusdisconnectedLW:
					pending_mid_recipients.erase(membername)
					clock_estimates.erase(membername)
					var member = Members.get_node_or_null(membername)
					if member:
						Members.remove_child(member)
					else:
						$MQTT.publish("%s/%s/status" % [roomtopic, membername], "".to_ascii_buffer(), true)
		elif stopic[roomtopicwords+1].substr(0, 5) == "audio":
			var member = Members.get_node_or_null(membername)
			if membername == myname:
				pass
			else:
				var control_packet := TwoVoipPacket.decode_control_packet(msg)
				if _handle_clock_control(membername, control_packet,
						arrival_time_usec, bool(packet_context.get("replay", false))):
					return
				if not connection_announced:
					return
				if member:
					if TwoVoipPacket.hash_response_is_valid(control_packet):
						get_node("../TwoVoipMic").receive_audio_hash_response(
								membername, control_packet)
						return
					if stopic[roomtopicwords+1] == "audio":
						member.receivemqttaudio(msg, packet_context)
					else:
						var atopic = stopic[roomtopicwords+1].split("/", true, 3)
						if len(atopic) >= 2 and atopic[1] == "meta":
							if len(atopic) == 2 or atopic[2] == myname:
								member.receivemqttaudiometa(msg, packet_context)
						else:
							assert(false)
				else:
					print("-- ", myname, " missing member: ", membername)
		else:
			print("Unrecognized topic ", stopic)
			
func on_broker_connect():
	network_ready = false
	network_ready_failed = false
	connection_announced = false
	clock_connection_generation += 1
	pending_ready_subscriptions.clear()
	pending_mid_recipients.clear()
	pending_clock_probes.clear()
	sent_clock_responses.clear()
	clock_estimates.clear()
	audioouttopic = ""
	audioouttopicmeta = ""
	$MQTT.publish(statustopic, Mstatusconnecting, true)
	subscribe_ready_channel("%s/+/status" % roomtopic)
	subscribe_ready_channel("%s/+/audio/meta" % roomtopic)
	subscribe_ready_channel("%s/+/audio" % roomtopic)
	subscribe_ready_channel("%s/+/audio/meta/%s" % [roomtopic, myname])

func on_broker_disconnect():
	network_ready = false
	connection_announced = false
	clock_connection_generation += 1
	print("MQTT broker disconnected")

func DDconn():
	print("eeeek CONNECTED ")
	
func D_input(event):
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_9:
		$MQTT.broker_connected.connect(DDconn)
#		if not $MQTT.connect_to_broker("tcp://mosquitto.doesliverpool.xyz:1883"):
#			print("BAD")
#		return
		
		# this works
		#$MQTT.set_last_will("room1/Larry_21ee/status", "discon".to_ascii_buffer(), true)

		#this doesn't work
		$MQTT.set_last_will("godot/twovoip/room1/Larry_21ee/status", "disconnected-LW".to_ascii_buffer(), true)

		var u = "rpoDYSwsYRfBAVxbtTuCc0ZLKw6rgC5yyFAVrYmeHVRHZaz5f2y3EUfR0klbTuhy"
		$MQTT.set_user_pass(u, "")
		var b = "wss://mqtt.flespi.io:443"
		if not $MQTT.connect_to_broker(b):
			print("BAD")


func _on_connect_toggled(toggled_on):
	var LogButton = get_node("../HBoxLogging/LogButton")
	get_node("../HBoxLogging/ReplayButton").disabled = toggled_on
	LogButton.disabled = toggled_on
	if toggled_on:
		if LogButton.button_pressed:
			flogfile = FileAccess.open("user://mqttlogging.dat", FileAccess.WRITE)
			print("Opening mqtt logfile ", flogfile.get_path_absolute())
			logfilepackcount = 0
			recording_start_ticks_msec = Time.get_ticks_msec()
			recording_start_unix_usec = \
					int(Time.get_unix_time_from_system() * 1000000.0)
		$MQTT.received_message.connect(received_mqtt)
		$MQTT.broker_connected.connect(on_broker_connect)
		$MQTT.broker_disconnected.connect(on_broker_disconnect)
		$MQTT.subscribe_acknowledge.connect(on_subscribe_acknowledge)
		randomize()
		var FriendlyName = get_node("../HBoxMosquitto/FriendlyName")
		myname = "%s_%x" % [FriendlyName.text, (randi() % 0x10000)]
		$MQTT.client_id = "c%d" % (2 + (randi()%0x7fffff8))
		SelfMember.setname(myname)
		if flogfile != null:
			flogfile.store_line("%d %s %d" % [
					recording_start_ticks_msec, myname,
					recording_start_unix_usec])
		SelfMember.color = FriendlyName.get("theme_override_styles/normal").bg_color
		$GridContainer/topic.editable = false
		$GridContainer/broker.editable = false
		$GridContainer/presets.disabled = true

		roomtopic = $GridContainer/topic.text
		roomtopicwords = len(roomtopic.split("/"))
		statustopic = "%s/%s/status" % [roomtopic, myname]
		$MQTT.set_last_will(statustopic, MstatusdisconnectedLW, true)
		var userpass = ""
		if $GridContainer/mqttuser.text != "":
			$MQTT.set_user_pass($GridContainer/mqttuser.text, $GridContainer/mqttpassword.text)
			userpass = " -u %s -P %s" % [$GridContainer/mqttuser.text, $GridContainer/mqttpassword.text]
		else:
			$MQTT.set_user_pass(null, null)
		var brokerurl = $GridContainer/broker.text
		if brokerurl.find("://") == -1 and OS.has_feature("web"):
			brokerurl = "wss://"+brokerurl
		if not $MQTT.connect_to_broker(brokerurl):
			$Connect.button_pressed = false

		$Connect/ColorRectConnecting.visible = true
		#get_node("../HBoxMosquitto/Cmd").text = "mosquitto_sub -h %s%s -v -t %s/# -T %s/+/audio" % [$GridContainer/broker.text, userpass, $GridContainer/topic.text, $GridContainer/topic.text] 
		get_node("../HBoxMosquitto/Cmd").text = "mosquitto_sub -h %s%s -v -t %s/#" % [$GridContainer/broker.text, userpass, $GridContainer/topic.text] 
		print("mosquitto_sub -h %s%s -v -t %s/#" % [$GridContainer/broker.text, userpass, $GridContainer/topic.text]) 
		if OS.has_feature("web"):
			get_node("../HBoxMosquitto/Cmd").enabroomtopicwordsled = true

	else:
		if flogfile != null:
			print("Closing mqtt logfile ", flogfile.get_path_absolute())
			flogfile.close()
			flogfile = null
		print("Disconnecting MQTT")
		$Connect/ColorRectConnecting.visible = false
		$MQTT.received_message.disconnect(received_mqtt)
		$MQTT.broker_connected.disconnect(on_broker_connect)
		$MQTT.broker_disconnected.disconnect(on_broker_disconnect)
		$MQTT.subscribe_acknowledge.disconnect(on_subscribe_acknowledge)
		$MQTT.publish(statustopic, Mstatusdisconnected, true)
		$MQTT.disconnect_from_server()
		while Members.get_child_count() >= 2:
			Members.remove_child(Members.get_child(Members.get_child_count() - 1))
		$GridContainer/broker.editable = true
		$GridContainer/topic.editable = true
		$GridContainer/presets.disabled = false
		myname = ""
		SelfMember.setname("Self")
		audioouttopic = ""
		audioouttopicmeta = ""
		statustopic = ""

func _on_mqtt_broker_connection_failed():
	$Connect.button_pressed = false

func _on_replay_button_toggled(toggled_on):
	if not toggled_on:
		return
	print("*** Begin replay")
	var ReplayButton = get_node("../HBoxLogging/ReplayButton")
	var flogfileR : FileAccess = FileAccess.open("user://mqttlogging.dat", FileAccess.READ)
	if flogfileR == null:
		push_warning("No MQTT recording found at %s" % logfile)
		ReplayButton.button_pressed = false
		return
	var sl0 = flogfileR.get_line().split(" ", false)
	if sl0.size() < 2:
		push_warning("Malformed MQTT recording header")
		ReplayButton.button_pressed = false
		flogfileR.close()
		return
	var timediff0 = int(sl0[0]) - Time.get_ticks_msec()
	var replay_recording_start_ticks_msec := int(sl0[0])
	myname = sl0[1]
	var recording_key := "%d:%s" % [replay_recording_start_ticks_msec, myname]
	if sl0.size() >= 3:
		replay_arrival_epoch_usec = int(sl0[2])
		replay_recording_key = recording_key
	elif replay_recording_key != recording_key:
		# Legacy recordings did not save receiver Unix time. Choose one mapping
		# once, retain it for every replay, and make the approximation explicit.
		replay_arrival_epoch_usec = \
				int(Time.get_unix_time_from_system() * 1000000.0)
		replay_recording_key = recording_key
		push_warning("Legacy LogRec has no receiver Unix epoch; fixing replay epoch at %d" \
				% replay_arrival_epoch_usec)
	SelfMember.setname(myname)
	roomtopic = $GridContainer/topic.text
	roomtopicwords = len(roomtopic.split("/"))
	audioouttopic = "%s/%s/audio" % [roomtopic, myname]
	audioouttopicmeta = "%s/%s/audio/meta" % [roomtopic, myname]
	statustopic = "%s/%s/status" % [roomtopic, myname]
	# Replay has no asynchronous channels to subscribe. Once its recorded room
	# identity and topics exist, the offline transport is fully ready.
	network_ready = true
	connection_announced = true

	var l = flogfileR.get_line()
	var loglinenumber = 1
	while ReplayButton.button_pressed and l:
		var sl = l.split(" ", false, 2)
		if sl.size() < 3:
			push_warning("Skipping malformed MQTT recording line %d" % loglinenumber)
			l = flogfileR.get_line()
			loglinenumber += 1
			continue
		var timediff = int(sl[0]) - Time.get_ticks_msec()
		var dtms = timediff - timediff0
		if dtms > 1000:
			await get_tree().create_timer(0.9).timeout
			continue
		elif dtms > 0:
			await get_tree().create_timer(dtms/1000.0).timeout
		elif dtms < -1000:
			print("Long delay %f seconds, catching up " % (-dtms/1000.0))
			timediff0 = timediff
		print(l)
		if flogfile == null:
			var recorded_payload := decode_log_payload(sl[2])
			var recorded_ticks_msec := int(sl[0])
			received_mqtt(sl[1], recorded_payload, {
					"record_packet_index": loglinenumber,
					"recording_start_ticks_msec": replay_recording_start_ticks_msec,
					"recorded_ticks_msec": recorded_ticks_msec,
					"arrival_time_usec": replay_arrival_epoch_usec \
							+ (recorded_ticks_msec \
							- replay_recording_start_ticks_msec) * 1000,
					"replay": true,
			})
		get_node("../HBoxLogging/PacketCount").text = str(logfilepackcount)
		l = flogfileR.get_line()
		loglinenumber += 1
		get_node("../HBoxLogging/PacketCount").text = "%d/%d" % [loglinenumber, logfilepackcount]
	ReplayButton.button_pressed = false
	flogfileR.close()
	print("*** End replay")
	
