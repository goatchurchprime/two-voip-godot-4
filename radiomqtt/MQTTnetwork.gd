extends Control

var myname = ""
var roomtopic = ""
var audioouttopic = "" # "%s/%s/audio"
var statustopic = ""

@onready var Members = get_node("../Members")

func _ready():
	if $GridContainer/presets.selected == -1:
		$GridContainer/presets.select(0)
	_on_mqtt_broker_item_selected($GridContainer/presets.selected)

func _on_mqtt_broker_item_selected(index):
	var preset = $GridContainer/presets.text
	$GridContainer/mqttuser.text = ""
	$GridContainer/mqttpassword.text = ""
	$GridContainer/topic.text = "twovoip/myroom"
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


func transportaudiopacket(packet):
	if audioouttopic:
		$MQTT.publish(audioouttopic, packet)

func received_mqtt(topic, msg):
	var stopic = topic.split("/")
	if len(stopic) == 4:
		var membername = stopic[2]
		if stopic[3] == "status" and membername != myname:
			if msg == "alive".to_ascii_buffer():
				var member = load("res://radiomqtt/member.tscn").instantiate()
				member.setname(membername)
				Members.add_child(member)
				$MQTT.subscribe("%s/%s/audio" % [roomtopic, membername])
			elif msg == "dead".to_ascii_buffer():
				var member = Members.get_node_or_null(membername)
				if member:
					Members.remove_child(member)
					$MQTT.unsubscribe("%s/%s/audio" % [roomtopic, membername])
				else:
					$MQTT.publish("%s/%s/status" % [roomtopic, membername], "".to_ascii_buffer(), true)
		if stopic[3] == "audio":
			Members.get_node(membername).receivemqttmessage(msg)
			
func on_broker_connect():
	$MQTT.subscribe("%s/+/status" % roomtopic)
	$MQTT.publish(statustopic, "alive".to_ascii_buffer(), true)

func on_broker_disconnect():
	print("MQTT broker disconnected")

func _on_connect_toggled(toggled_on):
	if toggled_on:
		$MQTT.received_message.connect(received_mqtt)
		$MQTT.broker_connected.connect(on_broker_connect)
		$MQTT.broker_disconnected.connect(on_broker_disconnect)
		randomize()
		$MQTT.client_id = "c%d" % (2 + (randi()%0x7fffff8))
		myname = $MQTT.client_id
		Members.get_node("Self/Label").text = myname
		$GridContainer/topic.editable = false
		$GridContainer/broker.editable = false
		$GridContainer/presets.disabled = true

		roomtopic = $GridContainer/topic.text
		audioouttopic = "%s/%s/audio" % [roomtopic, myname]
		statustopic = "%s/%s/status" % [roomtopic, myname]
		$MQTT.set_last_will(statustopic, "dead".to_ascii_buffer(), true)
		var userpass = ""
		if $GridContainer/mqttuser.text != "":
			$MQTT.set_user_pass($GridContainer/mqttuser.text, $GridContainer/mqttpassword.text)
			userpass = " -u %s -P %s" % [$GridContainer/mqttuser.text, $GridContainer/mqttpassword.text]
		else:
			$MQTT.set_user_pass(null, null)
		$MQTT.connect_to_broker($GridContainer/broker.text)
		get_node("../HBoxMosquitto/Cmd").text = "mosquitto_sub -h %s%s -v -t %s/# -T %s/+/audio" % [$GridContainer/broker.text, userpass, $GridContainer/topic.text, $GridContainer/topic.text] 

	else:
		print("Disconnecting MQTT")
		$MQTT.received_message.disconnect(received_mqtt)
		$MQTT.broker_connected.disconnect(on_broker_connect)
		$MQTT.broker_disconnected.disconnect(on_broker_disconnect)
		$MQTT.publish(statustopic, "dead".to_ascii_buffer(), true)
		$MQTT.disconnect_from_server()
		while Members.get_child_count() >= 2:
			Members.remove_child(Members.get_child(Members.get_child_count() - 1))
		$GridContainer/broker.editable = true
		$GridContainer/topic.editable = true
		$GridContainer/presets.disabled = false
		myname = ""
		Members.get_node("Self/Label").text = "Self"
		audioouttopic = ""
		statustopic = ""


