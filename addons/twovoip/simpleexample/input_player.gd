extends Control

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

func _on_feedback_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_voxthreshhold(event.position.x/$FeedbackDisplay.size.x)
