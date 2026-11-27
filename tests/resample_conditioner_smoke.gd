extends SceneTree


func _initialize() -> void:
	const INPUT_RATE := 44100
	const OUTPUT_RATE := 48000
	const INPUT_CHUNK := 882
	const OUTPUT_CHUNK := 960
	var conditioner := TwoVoipConditioner.new()
	assert(conditioner.initialize(20, INPUT_RATE, OUTPUT_RATE, 2) == OK)
	assert(conditioner.get_input_chunk_size() == INPUT_CHUNK)
	assert(conditioner.get_output_chunk_size() == OUTPUT_CHUNK)

	var input := PackedVector2Array()
	input.resize(INPUT_CHUNK)
	var output_energy := 0.0
	for chunk in range(10):
		for frame in range(INPUT_CHUNK):
			var sample := sin(TAU * 440.0 * (chunk * INPUT_CHUNK + frame) / INPUT_RATE)
			input[frame] = Vector2(sample, -sample)
		var output := conditioner.condition(input, PackedVector2Array())
		assert(output.size() == OUTPUT_CHUNK)
		for frame in output:
			assert(absf(frame.x + frame.y) < 0.0001)
			output_energy += frame.length_squared()
	assert(output_energy > 1.0)
	assert(conditioner.get_peak() > 0.9)
	assert(conditioner.get_rms() > 0.1)
	conditioner.set_gain(0.5)
	conditioner.condition(input, PackedVector2Array())
	assert(conditioner.get_gain() == 0.5)
	assert(conditioner.get_peak() > 0.4 and conditioner.get_peak() < 0.6)
	assert(conditioner.condition(input.slice(1), PackedVector2Array()).is_empty())
	assert(conditioner.get_peak() == 0.0)
	assert(conditioner.get_rms() == 0.0)

	var passthrough := TwoVoipConditioner.new()
	assert(passthrough.initialize(20, INPUT_RATE, INPUT_RATE, 2) == OK)
	assert(passthrough.condition(input, PackedVector2Array()) == input)

	var mono := TwoVoipConditioner.new()
	assert(mono.initialize(20, INPUT_RATE, OUTPUT_RATE, 1) == OK)
	for frame in range(INPUT_CHUNK):
		var sample := sin(TAU * 440.0 * frame / INPUT_RATE)
		input[frame] = Vector2(sample, sample * 0.5)
	var mono_output := mono.condition(input, PackedVector2Array())
	assert(mono_output.size() == OUTPUT_CHUNK)
	var mono_energy := 0.0
	for frame in mono_output:
		assert(frame.x == frame.y)
		mono_energy += frame.length_squared()
	assert(mono_energy > 1.0)

	var mono_passthrough := TwoVoipConditioner.new()
	assert(mono_passthrough.initialize(20, INPUT_RATE, INPUT_RATE, 1) == OK)
	mono_output = mono_passthrough.condition(input, PackedVector2Array())
	for frame in range(INPUT_CHUNK):
		var expected := (input[frame].x + input[frame].y) * 0.5
		assert(mono_output[frame] == Vector2(expected, expected))
	print("Mono and stereo Speex resampler conditioner smoke passed")
	quit(0)
