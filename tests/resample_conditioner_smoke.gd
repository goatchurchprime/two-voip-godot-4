extends SceneTree


func _initialize() -> void:
	const INPUT_RATE := 44100
	const OUTPUT_RATE := 48000
	const INPUT_CHUNK := 882
	const OUTPUT_CHUNK := 960
	var conditioner := TwoVoipConditioner.new()
	assert(conditioner.initialize(20, INPUT_RATE, OUTPUT_RATE) == OK)
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

	var passthrough := TwoVoipConditioner.new()
	assert(passthrough.initialize(20, INPUT_RATE, INPUT_RATE) == OK)
	assert(passthrough.condition(input, PackedVector2Array()) == input)
	print("Stereo Speex resampler conditioner smoke passed")
	quit(0)
