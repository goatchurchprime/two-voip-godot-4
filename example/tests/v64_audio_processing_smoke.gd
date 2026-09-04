extends SceneTree


func make_stereo(count: int, amplitude: float = 0.1) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in range(count):
		var left := amplitude * sin(TAU * 440.0 * i / 44100.0)
		var right := amplitude * sin(TAU * 660.0 * i / 44100.0)
		frames[i] = Vector2(left, right)
	return frames


func _initialize() -> void:
	var encoder := TwovoipOpusEncoder.new()
	assert(encoder.create_sampler(44100, 48000, 2, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(encoder.get_required_input_chunk_size() == 882)
	assert(not encoder.has_method("fetch_pre_encoded_chunk"))
	for property_name in ["output_chunk_size", "required_input_chunk_size", "gain", "agc_gain", "agc_mode", "denoiser", "peak", "rms", "speech_probability"]:
		var property = encoder.get_property_list().filter(func(item): return item.name == property_name)
		assert(property.size() == 1)
		assert(property[0].usage & PROPERTY_USAGE_READ_ONLY)

	encoder.set_gain(0.5)
	var frames := make_stereo(882)
	assert(encoder.process_chunk(frames) == 882)
	assert(abs(encoder.get_gain() - 0.5) < 0.0001)
	assert(encoder.get_peak() > 0.0)
	assert(encoder.get_rms() > 0.0)

	var short_frames := make_stereo(881)
	assert(encoder.process_chunk(short_frames) == -1)

	var fractional := TwovoipOpusEncoder.new()
	assert(fractional.create_sampler(44117, 48000, 2, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(fractional.get_required_input_chunk_size() == 883)
	var consumed := fractional.process_chunk(make_stereo(883))
	assert(consumed == 882 or consumed == 883)

	var mono := TwovoipOpusEncoder.new()
	assert(mono.create_sampler(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(mono.get_required_input_chunk_size() == 960)
	assert(mono.process_chunk(make_stereo(960)) == 960)

	for output_rate in [8000, 12000, 16000, 24000, 48000]:
		for duration_ms in [10, 20, 40, 60]:
			var standard := TwovoipOpusEncoder.new()
			var output_frames: int = output_rate * duration_ms / 1000
			assert(standard.create_sampler(44100, output_rate, 2, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, output_frames) == OK)
			assert(standard.get_required_input_chunk_size() == 44100 * duration_ms / 1000)
			var standard_required: int = standard.get_required_input_chunk_size()
			var standard_consumed: int = standard.process_chunk(make_stereo(standard_required))
			assert(standard_consumed > 0 and standard_consumed <= standard_required)

	var voice := TwovoipOpusEncoder.new()
	assert(voice.create_sampler(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_SPEEX, TwovoipOpusEncoder.AGC_APPLIED, 960) == OK)
	voice.set_gain(0.75)
	assert(voice.process_chunk(make_stereo(960)) == 960)
	assert(voice.get_agc_gain() > 0.0)
	assert(abs(voice.get_gain() - 0.75) < 0.0001)

	var rnnoise_voice := TwovoipOpusEncoder.new()
	assert(rnnoise_voice.create_sampler(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_RNNOISE, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(rnnoise_voice.get_denoiser() == TwovoipOpusEncoder.DENOISER_RNNOISE)
	assert(rnnoise_voice.process_chunk(make_stereo(960)) == 960)
	var invalid_rnnoise := TwovoipOpusEncoder.new()
	assert(invalid_rnnoise.create_sampler(48000, 48000, 2, TwovoipOpusEncoder.DENOISER_RNNOISE, TwovoipOpusEncoder.AGC_DISABLED, 960) != OK)

	var legacy := TwovoipOpusEncoder.new()
	assert(legacy.create_sampler(44100, 48000, 2, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(legacy.create_opus_encoder(12000, 5, true))
	assert(legacy.process_pre_encoded_chunk(make_stereo(882), 960, false, false) > 0.0)
	assert(not legacy.encode_chunk().is_empty())

	print("audio processing smoke passed: native voice processing, gain, rates, frames, stereo and mono")
	quit()
