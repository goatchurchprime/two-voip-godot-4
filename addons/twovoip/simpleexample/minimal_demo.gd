extends Control

func _ready():
	$InputPlayer/TwoVoipMic.connect("transmit_audio_json_packet", on_transmit_audio_json_packet)
	$InputPlayer/TwoVoipMic.connect("transmit_audio_packet", on_transmit_audio_packet)

func set_receiving(playername, toggled_on):
	if toggled_on:
		add_receiving_player(playername)
	else:
		remove_receiving_player(playername)

# When a player talks they send a stream of audio packets
# with a JSON encoded header and footer to bookend the stream.
# The new_output_players is the list of players who might 
# have joined mid-stream and require a mid-stream header pick up
# and decode the audio stream that is active.

var output_players : Array[String]
var new_output_players : Array[String]

func add_receiving_player(playername):
	output_players.append(playername)
	new_output_players.append(playername)

func remove_receiving_player(playername):
	output_players.erase(playername)
	new_output_players.erase(playername)

func on_transmit_audio_json_packet(jsonpacket : Dictionary):
	if jsonpacket.has("talkingtimestart"):
		new_output_players.clear()
	on_transmit_audio_packet(JSON.stringify(jsonpacket).to_ascii_buffer())

func on_transmit_audio_packet(packet : PackedByteArray):
	if new_output_players:
		var audio_stream_packet_mid_header = $InputPlayer/TwoVoipMic.request_audio_json_packet_mid_header()
		if audio_stream_packet_mid_header:
			for player in new_output_players:
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
