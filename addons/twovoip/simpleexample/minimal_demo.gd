extends Control

func _ready():
	$InputPlayer.networkingnode = self
	for player in $OutputPlayers.get_children():
		player.networkingnode = self

func RPC_incomingaudiopacket(playername, packet):
	var player = $OutputPlayers.get_node_or_null(playername)
	if player:
		player.RPC_incomingaudiopacket(packet)
	else:
		print("missing output player")

func set_receiving(playername, toggled_on):
	if toggled_on:
		$InputPlayer.add_receiving_player(playername)
