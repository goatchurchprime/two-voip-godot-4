extends Control

func _ready():
	$InputPlayer/TwoVoipMic.connect("transmit_audio_json_packet", on_transmit_audio_json_packet)
	$InputPlayer/TwoVoipMic.connect("transmit_audio_packet", on_transmit_audio_packet)

func set_receiving(playername, toggled_on):
	if toggled_on:
		add_receiving_player(playername)
	else:
		remove_receiving_player(playername)

# Handle data transmission to other players
# Each voice stream has a header and footer in json form
# The complexity is to handle someone joining mid-stream who needs a valid header to be sent 

var output_players : Array[String]
var new_output_players : Array[String]
var removed_output_players : Array[String]
var recorded_audio_stream_packet_header = null

func add_receiving_player(playername):
	output_players.append(playername)
	new_output_players.append(playername)

func remove_receiving_player(playername):
	assert (output_players.has(playername))
	output_players.erase(playername)
	new_output_players.erase(playername)

func on_transmit_audio_json_packet(jsonpacket : Dictionary):
	if jsonpacket.has("talkingtimestart"):
		recorded_audio_stream_packet_header = jsonpacket
		new_output_players.clear()
	var opusframecount = recorded_audio_stream_packet_header["opusframecount"]
	if jsonpacket.has("talkingtimeend"):
		opusframecount += 1
		recorded_audio_stream_packet_header = null
	on_transmit_audio_packet(JSON.stringify(jsonpacket).to_ascii_buffer(), opusframecount)

func on_transmit_audio_packet(packet : PackedByteArray, opusframecount : int):
	if recorded_audio_stream_packet_header:
		recorded_audio_stream_packet_header["opusframecount"] = opusframecount
	if new_output_players:
		var audio_stream_packet_mid_header = $InputPlayer/TwoVoipMic.request_audio_json_packet_mid_header()
		if audio_stream_packet_mid_header:
			for player in new_output_players:
				prints("** sending missing start to ", player, recorded_audio_stream_packet_header, opusframecount, recorded_audio_stream_packet_header["opusframecount"])
				RPC_incomingaudiopacket(player, JSON.stringify(audio_stream_packet_mid_header).to_ascii_buffer())
		new_output_players.clear()
	for player in output_players:
		RPC_incomingaudiopacket(player, packet)

func RPC_incomingaudiopacket(playername, packet):
	var player = $OutputPlayers.get_node_or_null(playername)
	if player:
		player.RPC_incomingaudiopacket(packet)
	else:
		print("missing output player")
