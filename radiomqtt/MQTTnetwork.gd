extends Control

var myname = ""
var audioouttopic = "" # "%s/%s/audio"
var statustopic = ""

func transportaudiopacket(packet):
	if audioouttopic:
		$MQTT.publish(audioouttopic, packet)

func received_mqtt(topic, msg):
	var stopic = topic.split("/")
	if len(stopic) == 4:
		var membername = stopic[2]
		if stopic[3] == "status" and membername != myname:
			if msg == "alive".to_ascii_buffer():
				var member = load("res://member.tscn").instantiate()
				member.setname(membername)
				$Members.add_child(member)
				$MQTT.subscribe("twovoip/%s/%s/audio" % [$roomname.text, membername])
			elif msg == "dead".to_ascii_buffer():
				var member = $Members.get_node_or_null(membername)
				if member:
					$Members.remove_child(member)
					$MQTT.unsubscribe("twovoip/%s/%s/audio" % [$roomname.text, membername])
		if stopic[3] == "audio":
			$Members.get_node(membername).audiopacketsbuffer.push_back(msg)
			
func on_broker_connect():
	$roomname.editable = false
	$MQTT.subscribe("twovoip/%s/+/status" % $roomname.text)
	$MQTT.publish(statustopic, "alive".to_ascii_buffer(), true)

func on_broker_disconnect():
	print("MQTT broker disconnected")
	$roomname.editable = true

func _on_connect_mqtt_toggled(toggled_on):
	if toggled_on:
		$MQTT.received_message.connect(received_mqtt)
		$MQTT.broker_connected.connect(on_broker_connect)
		$MQTT.broker_disconnected.connect(on_broker_disconnect)
		randomize()
		$MQTT.client_id = "c%d" % (2 + (randi()%0x7ffffff8))
		myname = $MQTT.client_id
		audioouttopic = "twovoip/%s/%s/audio" % [$roomname.text, myname]
		statustopic = "twovoip/%s/%s/status" % [$roomname.text, myname]
		$MQTTBroker.editable = true
		$MQTT.set_last_will(statustopic, "dead".to_ascii_buffer(), true)
		$MQTT.connect_to_broker($MQTTBroker.text)
				
	else:
		print("Disconnecting MQTT")
		$MQTT.received_message.disconnect(received_mqtt)
		$MQTT.broker_connected.disconnect(on_broker_connect)
		$MQTT.broker_disconnected.disconnect(on_broker_disconnect)
		$MQTT.publish(statustopic, "dead".to_ascii_buffer(), true)
		$MQTT.disconnect_from_server()
		for m in $Members.get_children():
			$Members.remove_child(m)
		audioouttopic = ""
		statustopic = ""
