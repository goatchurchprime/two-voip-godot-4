extends Control

func _ready():
	# Wire up the optional controls and feedback from your UI
	$TwoVoipMic.init_voip_mic($MicOnButton,
							  $InputOptionButton,
							  $PTTButton,
							  $VoxButton,
							  $DenoiseButton,
							  $FeedbackDisplay.material)

	# Set up the opus compression library
	$TwoVoipMic.set_opus_values(48000, 20, 2, 12000, 5, true)

	# Set the threshold for voice activation
	$TwoVoipMic.set_vox_threshhold(0.02)

func _on_feedback_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_voxthreshhold(event.position.x/$FeedbackDisplay.size.x)
