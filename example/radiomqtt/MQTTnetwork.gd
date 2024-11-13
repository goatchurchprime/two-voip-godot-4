extends Control

var myname = ""
var roomtopic = ""
var roomtopicwords = 0
var audioouttopic = "" 
var audioouttopicmeta = "" 
var statustopic = ""

@onready var Members = get_node("../Members")
@onready var SelfMember = get_node("../Members/Self")

@onready var Mstatusconnected = "connected".to_ascii_buffer()
@onready var Mstatusdisconnected = "disconnnected".to_ascii_buffer()
@onready var MstatusdisconnectedLW = "disconnected-LW".to_ascii_buffer()

const logfile = "user://mqttlogging.dat"
var flogfile : FileAccess = null
var logfilepackcount = 0

func _ready():
	if $GridContainer/presets.selected == -1:
		$GridContainer/presets.select(0)
	_on_mqtt_broker_item_selected($GridContainer/presets.selected)

func _on_mqtt_broker_item_selected(index):
	var preset = $GridContainer/presets.text
	$GridContainer/mqttuser.text = ""
	$GridContainer/mqttpassword.text = ""
	$GridContainer/topic.text = "godot/twovoip/room1"
	if preset == "hivemq":
		$GridContainer/broker.text = "broker.hivemq.com"
	elif preset == "m.org":
		$GridContainer/broker.text = "test.mosquitto.org"
	elif preset == "hass":
		$GridContainer/broker.text = "homeassistant.local"
		$GridContainer/mqttuser.text = "mqttuser"
		$GridContainer/mqttpassword.text = "mqttpwd"
	else:
		$GridContainer/broker.text = "mosquitto.doesliverpool.xyz"

func transportaudiopacket(packet, asbase64):
	if audioouttopic:
		if asbase64:
			$MQTT.publish(audioouttopic, Marshalls.raw_to_base64(packet).to_ascii_buffer())
		else:
			$MQTT.publish(audioouttopic, packet)

func transportaudiopacketjson(jheader):
	if audioouttopicmeta:
		var packet = JSON.stringify(jheader).to_ascii_buffer()
		$MQTT.publish(audioouttopicmeta, packet)

func received_mqtt(topic, msg):
	if flogfile != null:
		flogfile.store_line("%d %s %s" % [Time.get_ticks_msec(), topic, msg.get_string_from_ascii()]) 
		logfilepackcount += 1
		get_node("../HBoxLogging/PacketCount").text = str(logfilepackcount)
	var stopic = topic.split("/", true, roomtopicwords+1)
	if len(stopic) == roomtopicwords + 2:
		var membername = stopic[roomtopicwords]
		if stopic[roomtopicwords+1] == "status":
			if membername != myname:
				if msg == Mstatusconnected:
					var member = load("res://radiomqtt/member.tscn").instantiate()
					member.setname(membername)
					Members.add_child(member)
					$MQTT.subscribe("%s/%s/audio/meta" % [roomtopic, membername])
					$MQTT.subscribe("%s/%s/audio" % [roomtopic, membername])
				elif msg == Mstatusdisconnected or msg == MstatusdisconnectedLW:
					var member = Members.get_node_or_null(membername)
					if member:
						Members.remove_child(member)
						$MQTT.unsubscribe("%s/%s/audio/meta" % [roomtopic, membername])
						$MQTT.unsubscribe("%s/%s/audio" % [roomtopic, membername])
					else:
						$MQTT.publish("%s/%s/status" % [roomtopic, membername], "".to_ascii_buffer(), true)
		elif stopic[roomtopicwords+1] == "audio/meta":
			Members.get_node(membername).receivemqttaudiometa(msg)
		elif stopic[roomtopicwords+1] == "audio":
			Members.get_node(membername).receivemqttaudio(msg)
		else:
			print("Unrecognized topic ", stopic)
			
func on_broker_connect():
	$MQTT.subscribe("%s/+/status" % roomtopic)
	$MQTT.publish(statustopic, Mstatusconnected, true)
	$Connect/ColorRectConnecting.visible = false

func on_broker_disconnect():
	print("MQTT broker disconnected")

func DDconn():
	print("eeeek CONNECTED ")
	
func _input(event):
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
	LogButton.disabled = toggled_on
	if toggled_on:
		if LogButton.button_pressed:
			flogfile = FileAccess.open("user://mqttlogging.dat", FileAccess.WRITE)
			print("Opening mqtt logfile ", flogfile.get_path_absolute())
			logfilepackcount = 0
		$MQTT.received_message.connect(received_mqtt)
		$MQTT.broker_connected.connect(on_broker_connect)
		$MQTT.broker_disconnected.connect(on_broker_disconnect)
		randomize()
		var FriendlyName = get_node("../HBoxMosquitto/FriendlyName")
		myname = "%s_%x" % [FriendlyName.text, (randi() % 0x10000)]
		$MQTT.client_id = "c%d" % (2 + (randi()%0x7fffff8))
		SelfMember.setname(myname)
		if flogfile != null:
			flogfile.store_line("%d %s" % [Time.get_ticks_msec(), myname]) 
		SelfMember.color = FriendlyName.get("theme_override_styles/normal").bg_color
		$GridContainer/topic.editable = false
		$GridContainer/broker.editable = false
		$GridContainer/presets.disabled = true

		roomtopic = $GridContainer/topic.text
		roomtopicwords = len(roomtopic.split("/"))
		audioouttopic = "%s/%s/audio" % [roomtopic, myname]
		audioouttopicmeta = "%s/%s/audio/meta" % [roomtopic, myname]
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
	var sl0 = flogfileR.get_line().split(" ")
	var timediff0 = int(sl0[0]) - Time.get_ticks_msec()
	myname = sl0[1]
	SelfMember.setname(myname)
	roomtopic = $GridContainer/topic.text
	roomtopicwords = len(roomtopic.split("/"))
	audioouttopic = "%s/%s/audio" % [roomtopic, myname]
	audioouttopicmeta = "%s/%s/audio/meta" % [roomtopic, myname]
	statustopic = "%s/%s/status" % [roomtopic, myname]

	var l = flogfileR.get_line()
	while ReplayButton.button_pressed and l:
		var sl = l.split(" ")
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
			received_mqtt(sl[1], sl[2].to_ascii_buffer())
		l = flogfileR.get_line()
	ReplayButton.button_pressed = false
	flogfileR.close()
	print("*** End replay")
	
