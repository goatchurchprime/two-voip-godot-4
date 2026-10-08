extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker
var displayed_clock_revision := -1
var displayed_clock_valid := false
var is_local_member := false

func _ready():
	is_local_member = name == "Self"
	twovoipspeaker.init_voip_speaker($TimingMeter)
	_update_clock_offset_display()

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receive_mqtt_audio_packet(msg, transport_debug_context: Dictionary = {}):
	twovoipspeaker.receive_audio_packet(msg, transport_debug_context)

func _process(_delta):
	if displayed_clock_revision != twovoipspeaker.source_clock_offset_revision_count \
			or displayed_clock_valid != twovoipspeaker.source_clock_offset_bound_valid:
		_update_clock_offset_display()
	if twovoipspeaker.audio_stream_playback_opus and twovoipspeaker.audio_stream_playback_opus.is_playing():
		$AudioStreamPlayer.volume_db = $Node/Volume.value


func _update_clock_offset_display():
	displayed_clock_revision = twovoipspeaker.source_clock_offset_revision_count
	displayed_clock_valid = twovoipspeaker.source_clock_offset_bound_valid
	if is_local_member:
		$ClockOffset.text = "clock +0.0 ms · local"
		$ClockOffset.modulate = Color(0.45, 1.0, 0.58)
		$ClockOffset.tooltip_text = \
				"This member owns the local monotonic clock; its offset is exactly zero."
		return
	if not displayed_clock_valid:
		$ClockOffset.text = "clock pending"
		$ClockOffset.modulate = Color(0.72, 0.74, 0.78)
		$ClockOffset.tooltip_text = "No source clock offset has been selected yet."
		return
	var estimate_ms: float = twovoipspeaker.source_clock_offset_estimate_usec / 1000.0
	var uncertainty_ms: float = twovoipspeaker.source_clock_offset_uncertainty_usec / 1000.0
	var unix_ms: float = twovoipspeaker.source_clock_unix_estimate_usec / 1000.0
	$ClockOffset.text = "clock %+.1f · u%+.1f · r%d" % [
			estimate_ms, unix_ms, displayed_clock_revision] \
			if twovoipspeaker.source_clock_unix_estimate_valid \
			else "clock %+.1f ms · r%d" % [estimate_ms, displayed_clock_revision]
	$ClockOffset.modulate = Color(1.0, 0.82, 0.35)
	$ClockOffset.tooltip_text = \
			"Source clock offset: %+.3f ms\nUnix-derived offset: %+.3f ms\nSelected minus Unix: %+.3f ms\nBounds: [%+.3f, %+.3f] ms\nUncertainty: %.3f ms\nRTT: %.3f ms\nRevision: %d\nReason: %s" % [
				estimate_ms,
				unix_ms,
				twovoipspeaker.source_clock_estimate_minus_unix_usec / 1000.0,
				twovoipspeaker.source_clock_offset_lower_bound_usec / 1000.0,
				twovoipspeaker.source_clock_offset_upper_bound_usec / 1000.0,
				uncertainty_ms,
				twovoipspeaker.source_clock_probe_rtt_usec / 1000.0,
				displayed_clock_revision,
				twovoipspeaker.source_clock_revision_reason]
