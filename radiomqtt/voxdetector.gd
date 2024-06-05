extends HSlider

const outlinewidth = 4
var samplesrunon = 17
var samplescountdown = 0
var voxthreshold = 1.0
var visthreshold = 1.0

func _on_h_slider_vox_value_changed(v):
	voxthreshold = v/max_value
	
func _ready():
	await get_tree().process_frame 
	$ColorRectBackground.size = size
	$ColorRectLoudness.size = size
	$ColorRectLoudness2.size = Vector2(size.x, size.y/3)
	$ColorRectThreshold.position.y = 0
	$ColorRectThreshold.size.y = size.y
	$ColorRectThreshold.size.x = outlinewidth
	_on_h_slider_vox_value_changed(value)
	
func loudnessvalues(chunkv1, chunkv2):
	$ColorRectLoudness.size.x = size.x*chunkv1
	$ColorRectLoudness2.size.x = size.x*chunkv2
	if chunkv1 >= voxthreshold:
		if not $ColorRectThreshold.visible:
			visthreshold = chunkv1
			$ColorRectThreshold.visible = true
			if get_node("../Vox").pressed:
				get_node("../PTT").set_pressed(true)
		else:
			visthreshold = max(visthreshold, chunkv1)
		$ColorRectThreshold.position.x = size.x*visthreshold - outlinewidth/2.0
		samplescountdown = samplesrunon
	elif samplescountdown > 0:
		samplescountdown -= 1
		if samplescountdown == 0:
			$ColorRectThreshold.visible = false
			if get_node("../Vox").pressed:
				get_node("../PTT").set_pressed(false)
		
func _on_vox_toggled(toggled_on):
	get_node("../PTT").toggle_mode = toggled_on
	get_node("../PTT").set_pressed($ColorRectThreshold.visible and toggled_on)
