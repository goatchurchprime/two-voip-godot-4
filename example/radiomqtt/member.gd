extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker
@onready var colournormal = $Node/ColorRectBufferQueue.color
var colourfast = Color.GREEN
var colourslow = Color.ORANGE
var colourpause = Color.GRAY

var lag_sample_count := 0
var lag_current_ms := 0.0
var lag_average_ms := 0.0
var lag_minimum_ms := 0.0
var lag_maximum_ms := 0.0
var lag_m2 := 0.0

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receivemqttaudiometa(msg):
	twovoipspeaker.receive_audio_packet(msg)

func receivemqttaudio(msg):
	var arrival_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	twovoipspeaker.receive_audio_packet(msg)
	var capture_time_usec: int = twovoipspeaker.source_packet_first_frame_time_usec
	if capture_time_usec > 0:
		update_packet_lag((arrival_time_usec - capture_time_usec) / 1000.0)


func update_packet_lag(lag_ms: float):
	lag_current_ms = lag_ms
	lag_sample_count += 1
	if lag_sample_count == 1:
		lag_average_ms = lag_ms
		lag_minimum_ms = lag_ms
		lag_maximum_ms = lag_ms
	else:
		var previous_average := lag_average_ms
		lag_average_ms += (lag_ms - lag_average_ms) / lag_sample_count
		lag_m2 += (lag_ms - previous_average) * (lag_ms - lag_average_ms)
		lag_minimum_ms = min(lag_minimum_ms, lag_ms)
		lag_maximum_ms = max(lag_maximum_ms, lag_ms)
	update_lag_display()


func update_lag_display():
	var target_ms: float = twovoipspeaker.audio_buffer_lag_time_target * 1000.0
	var standard_deviation: float = sqrt(lag_m2 / maxi(1, lag_sample_count - 1))
	$LagText.text = "capture→arrival %.0f ms   avg %.0f   range %.0f–%.0f   target %.0f" % [
		lag_current_ms, lag_average_ms, lag_minimum_ms, lag_maximum_ms, target_ms]

	var scale_min: float = minf(0.0, lag_minimum_ms)
	var scale_max: float = maxf(100.0, maxf(target_ms * 1.2, lag_maximum_ms))
	var meter_width: float = $LagMeter.size.x
	var meter_scale: float = meter_width / (scale_max - scale_min)
	var range_start: float = (lag_minimum_ms - scale_min) * meter_scale
	var range_finish: float = (lag_maximum_ms - scale_min) * meter_scale
	$LagMeter/Range.position.x = range_start
	$LagMeter/Range.size.x = max(2.0, range_finish - range_start)
	$LagMeter/Average.position.x = (lag_average_ms - scale_min) * meter_scale - 1.0
	$LagMeter/Current.position.x = (lag_current_ms - scale_min) * meter_scale - 2.0
	$LagMeter/Target.position.x = (target_ms - scale_min) * meter_scale - 1.0
	var is_outlier: bool = lag_sample_count > 10 \
			and abs(lag_current_ms - lag_average_ms) > maxf(20.0, standard_deviation * 3.0)
	$LagMeter/Current.color = Color.RED if is_outlier else Color.YELLOW


var timedelaytohide = 0.1
var prevopusframecount = -1
func _process(delta):
	if twovoipspeaker.audio_stream_playback_opus:
		$Node/ColorRectBufferQueue.size.x = min(1.0, twovoipspeaker.audio_stream_playback_opus.queue_length_frames()/twovoipspeaker.opus_sample_rate/twovoipspeaker.audio_buffer_length)*size.x
		$AudioStreamPlayer.volume_db = $Node/Volume.value
		var chunkv1 = twovoipspeaker.audio_stream_playback_opus.get_tail_max(twovoipspeaker.opusframesize)
		if chunkv1 != 0.0:
			chunkv1 = min(chunkv1*10, 1.0)
			$Node/ColorRectLoudness.size.x = chunkv1*size.x
			timedelaytohide = 0.1
		prevopusframecount = twovoipspeaker.opusframecount

		if $AudioStreamPlayer.pitch_scale == 1.0:
			$Node/ColorRectBufferQueue.color = colournormal
		else:
			$Node/ColorRectBufferQueue.color = colourslow if $AudioStreamPlayer.pitch_scale < 1.0 else colourfast

	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectLoudness.size.x = 0
