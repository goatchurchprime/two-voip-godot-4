extends Control

const outlinewidth = 4
var samplesrunon = 17
var samplescountdown = 0
var voxthreshold = 1.0
var visthreshold = 1.0

func _on_h_slider_vox_value_changed(value):
	voxthreshold = value/$HSliderVox.max_value
	
func _ready():
	$ColorRectLoudness.position.x = $HSliderVox.position.x
	$ColorRectLoudness.position.y = $HSliderVox.position.y - ($ColorRectLoudness.size.y - $HSliderVox.size.y)*0.5
	$ColorRectOutline.position = $ColorRectLoudness.position - Vector2(outlinewidth, outlinewidth)
	$ColorRectOutline.size.x = $HSliderVox.size.x + outlinewidth*2
	$ColorRectOutline.size.y = $ColorRectLoudness.size.y + outlinewidth*2
	$ColorRectThreshold.position.y = $ColorRectOutline.position.y
	$ColorRectThreshold.size.y = $ColorRectOutline.size.y
	$ColorRectThreshold.size.x = outlinewidth
	_on_h_slider_vox_value_changed($HSliderVox.value)
	
func addwindow(v):
	$ColorRectLoudness.size.x = $HSliderVox.size.x*v
	if v >= voxthreshold:
		if not $ColorRectThreshold.visible:
			visthreshold = v
			$ColorRectThreshold.visible = true
		else:
			visthreshold = max(visthreshold, v)
		$ColorRectThreshold.position.x = $HSliderVox.position.x + visthreshold*$HSliderVox.size.x - outlinewidth/2.0
		samplescountdown = samplesrunon
	elif samplescountdown > 0:
		samplescountdown -= 1
		if samplescountdown == 0:
			$ColorRectThreshold.visible = false
		
