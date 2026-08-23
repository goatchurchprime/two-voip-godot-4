extends Control

func _ready():
	$InputPlayer/TwoVoipMic.connect("transmitaudiojsonpacket", on_transmitaudiojsonpacket)
	$InputPlayer/TwoVoipMic.connect("transmitaudiopacket", on_transmitaudiopacket)

func set_receiving(playername, toggled_on):
	if toggled_on:
		add_receiving_player(playername)
	else:
		remove_receiving_player(playername)

# Handle data transmission to other players
# Each voice stream has a header and footer in json form
# The complexity is to handle someone joining mid-stream who needs a valid header to be sent 

var outputplayers : Array[String]
var new_outputplayers : Array[String]
var removed_outputplayers : Array[String]
var recorded_audiostreampacketheader = null

func add_receiving_player(playername):
	outputplayers.append(playername)
	new_outputplayers.append(playername)

func remove_receiving_player(playername):
	assert (outputplayers.has(playername))
	outputplayers.erase(playername)
	new_outputplayers.erase(playername)

func on_transmitaudiojsonpacket(jsonpacket : Dictionary):
	if jsonpacket.has("talkingtimestart"):
		recorded_audiostreampacketheader = jsonpacket
		new_outputplayers.clear()
	var opusframecount = recorded_audiostreampacketheader["opusframecount"]
	if jsonpacket.has("talkingtimeend"):
		opusframecount += 1
		recorded_audiostreampacketheader = null
	on_transmitaudiopacket(JSON.stringify(jsonpacket).to_ascii_buffer(), opusframecount)

func on_transmitaudiopacket(packet : PackedByteArray, opusframecount : int):
	if recorded_audiostreampacketheader:
		recorded_audiostreampacketheader["opusframecount"] = opusframecount
	if new_outputplayers:
		for player in new_outputplayers:
			print("** sending missing start to ", player, recorded_audiostreampacketheader)
			RPC_incomingaudiopacket(player, JSON.stringify(recorded_audiostreampacketheader).to_ascii_buffer())
		new_outputplayers.clear()
	for player in outputplayers:
		RPC_incomingaudiopacket(player, packet)

func RPC_incomingaudiopacket(playername, packet):
	var player = $OutputPlayers.get_node_or_null(playername)
	if player:
		player.RPC_incomingaudiopacket(packet)
	else:
		print("missing output player")
