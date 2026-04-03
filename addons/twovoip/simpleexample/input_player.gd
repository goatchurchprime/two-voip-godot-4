extends Control

var networkingnode = null

func _ready():
	# Wire up the optional controls and feedback from your UI
	$TwoVoipMic.initvoipmic($MicOnButton, 
							$InputOptionButton, 
							$PTTButton, 
							$VoxButton, 
							$DenoiseButton, 
							$FeedbackDisplay.material)
							
	# Set up the opus compression library
	$TwoVoipMic.setopusvalues(48000, 20, 2, 12000, 5, true)

	# Set the threshold for voice activation
	$TwoVoipMic.set_voxthreshhold(0.02)
	
	# (Other settings such as automatic gain control will come later)

func _on_feedback_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_voxthreshhold(event.position.x/$FeedbackDisplay.size.x)


# Handle data transmission to other players
# Each voice stream has a header and footer in json form
# The complexity is to handle someone joining mid-stream who needs a valid header to be sent 

var outputplayers = [ ]
var new_outputplayers = [ ]
var recorded_audiostreampacketheader = null

func add_receiving_player(playername):
	outputplayers.append(playername)
	new_outputplayers.append(playername)

func transmitaudiojsonpacket(jsonpacket : Dictionary):
	if jsonpacket.has("talkingtimestart"):
		recorded_audiostreampacketheader = jsonpacket
		new_outputplayers.clear()
	var opusframecount = recorded_audiostreampacketheader["opusframecount"]
	if jsonpacket.has("talkingtimeend"):
		opusframecount += 1
		recorded_audiostreampacketheader = null
	transmitaudiopacket(JSON.stringify(jsonpacket).to_ascii_buffer(), opusframecount)

func transmitaudiopacket(packet : PackedByteArray, opusframecount : int):
	if recorded_audiostreampacketheader:
		recorded_audiostreampacketheader["opusframecount"] = opusframecount
	if new_outputplayers:
		for player in new_outputplayers:
			print("** sending missing start to ", player, recorded_audiostreampacketheader)
			networkingnode.RPC_incomingaudiopacket(player, JSON.stringify(recorded_audiostreampacketheader).to_ascii_buffer())
		new_outputplayers.clear()
	for player in outputplayers:
		networkingnode.RPC_incomingaudiopacket(player, packet)
