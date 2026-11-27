extends SceneTree


func _initialize() -> void:
	const INPUT_RATE := 44100
	const OUTPUT_RATE := 48000
	const INPUT_CHUNK := 882
	const OUTPUT_CHUNK := 960
	const ECHO_DELAY := INPUT_RATE * 60 / 1000
	var source := PackedFloat32Array()
	source.resize(INPUT_RATE * 6)
	var noise_state := 7
	for frame in range(source.size()):
		noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
		source[frame] = (noise_state / float(0x7fffffff) - 0.5) * 0.3

	var conditioner := TwoVoipWebRTCConditioner.new()
	conditioner.set_echo_cancel_enabled(true)
	conditioner.set_denoising_level(TwoVoipWebRTCConditioner.DENOISING_MODERATE)
	conditioner.set_agc_enabled(true)
	assert(conditioner.initialize(20, INPUT_RATE, OUTPUT_RATE) == OK)
	assert(conditioner.get_input_chunk_size() == INPUT_CHUNK)
	assert(conditioner.get_output_chunk_size() == OUTPUT_CHUNK)
	conditioner.set_denoising_level(TwoVoipWebRTCConditioner.DENOISING_DISABLED)
	conditioner.set_agc_enabled(false)
	conditioner.set_echo_cancel_enabled(false)
	conditioner.set_echo_cancel_enabled(true)
	conditioner.set_denoising_level(TwoVoipWebRTCConditioner.DENOISING_MODERATE)
	conditioner.set_agc_enabled(true)
	var input_energy := 0.0
	var output_energy := 0.0
	var input_frames := 0
	var output_frames := 0
	for chunk in range(250):
		var microphone := PackedVector2Array()
		var playback := PackedVector2Array()
		microphone.resize(INPUT_CHUNK)
		playback.resize(INPUT_CHUNK)
		for frame in range(INPUT_CHUNK):
			var source_frame := chunk * INPUT_CHUNK + frame
			var playback_sample := source[source_frame]
			var microphone_sample := source[maxi(0, source_frame - ECHO_DELAY)] * 0.55
			playback[frame] = Vector2(playback_sample, playback_sample)
			microphone[frame] = Vector2(microphone_sample, microphone_sample)
		var conditioned := conditioner.condition(microphone, playback)
		assert(conditioned.size() == OUTPUT_CHUNK)
		if chunk >= 150:
			for frame in microphone:
				input_energy += frame.length_squared()
				input_frames += 1
			for frame in conditioned:
				output_energy += frame.length_squared()
				output_frames += 1

	var energy_ratio := (output_energy / output_frames) / (input_energy / input_frames)
	assert(energy_ratio < 0.1)

	# A short AudioEffectCapture frontier is completed from the tail retained
	# from the preceding render block rather than dropping the microphone block.
	var microphone := PackedVector2Array()
	var short_playback := PackedVector2Array()
	microphone.resize(INPUT_CHUNK)
	short_playback.resize(INPUT_CHUNK - 37)
	assert(conditioner.condition(microphone, short_playback).size() == OUTPUT_CHUNK)
	conditioner.set_echo_cancel_enabled(false)
	assert(conditioner.condition(microphone, PackedVector2Array()).size() == OUTPUT_CHUNK)
	var native_rate_conditioner := TwoVoipWebRTCConditioner.new()
	assert(native_rate_conditioner.initialize(20, INPUT_RATE, INPUT_RATE) == OK)
	assert(native_rate_conditioner.condition(microphone, short_playback).size() == INPUT_CHUNK)
	print("WebRTC conditioner 44.1 to 48 kHz smoke passed (energy ratio %.4f)" % energy_ratio)
	quit(0)
