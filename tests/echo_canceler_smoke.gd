extends SceneTree


const SAMPLE_RATE := 44100
const FRAME_SIZE := 882 # 20 ms
const FRAME_COUNT := 120
const WINDOW_SIZE := 10
const REQUIRED_ATTENUATION_DB := -20.0
const REQUIRED_IMPROVEMENT_DB := 10.0


func source_sample(index: int) -> float:
	var time := float(index) / SAMPLE_RATE
	return 0.14 * sin(TAU * 271.0 * time) + 0.10 * sin(TAU * 733.0 * time) \
			+ 0.07 * sin(TAU * 1871.0 * time) + 0.04 * sin(TAU * 3199.0 * time)


func microphone_sample(index: int, echo_kind: String) -> float:
	if echo_kind == "identical":
		return source_sample(index)
	if echo_kind == "scaled":
		return 0.35 * source_sample(index)

	# A 35 ms acoustic delay followed by reflections at about 40 and 55 ms.
	var value := 0.0
	if index >= 1544:
		value += 0.55 * source_sample(index - 1544)
	if index >= 1765:
		value += 0.18 * source_sample(index - 1765)
	if index >= 2426:
		value += 0.09 * source_sample(index - 2426)
	return value


func make_block(frame_number: int, echo_kind: String, microphone: bool) -> PackedVector2Array:
	var block := PackedVector2Array()
	block.resize(FRAME_SIZE)
	for offset in FRAME_SIZE:
		var index := frame_number * FRAME_SIZE + offset
		var value := microphone_sample(index, echo_kind) if microphone else source_sample(index)
		block[offset] = Vector2(value, value)
	return block


func block_energy(block: PackedVector2Array) -> float:
	var result := 0.0
	for sample in block:
		result += sample.x * sample.x + sample.y * sample.y
	return result


func energy_ratio_db(output_energy: float, input_energy: float) -> float:
	return 10.0 * log(max(output_energy, 1e-20) / max(input_energy, 1e-20)) / log(10.0)


func run_echo_case(echo_kind: String) -> bool:
	var canceler: Variant = ClassDB.instantiate("TwoVoipEchoCanceler")
	if canceler == null or canceler.call("initialize", SAMPLE_RATE, FRAME_SIZE) != OK:
		push_error("Echo cancellation smoke test: could not initialize %s case" % echo_kind)
		return false

	var input_window_energy := 0.0
	var output_window_energy := 0.0
	var initial_attenuation_db := 0.0
	var final_attenuation_db := 0.0
	var first_20_db_frame := -1

	for frame_number in FRAME_COUNT:
		var playback := make_block(frame_number, echo_kind, false)
		var microphone := make_block(frame_number, echo_kind, true)
		var cleaned: PackedVector2Array = canceler.call("cancel_echo", microphone, playback)
		input_window_energy += block_energy(microphone)
		output_window_energy += block_energy(cleaned)

		if frame_number % WINDOW_SIZE == WINDOW_SIZE - 1:
			var attenuation_db := energy_ratio_db(output_window_energy, input_window_energy)
			if frame_number == WINDOW_SIZE - 1:
				initial_attenuation_db = attenuation_db
			if first_20_db_frame == -1 and attenuation_db <= REQUIRED_ATTENUATION_DB:
				first_20_db_frame = frame_number
			if frame_number == FRAME_COUNT - 1:
				final_attenuation_db = attenuation_db
			input_window_energy = 0.0
			output_window_energy = 0.0

	var adaptation_ms := (first_20_db_frame + 1) * FRAME_SIZE * 1000.0 / SAMPLE_RATE
	print("Echo cancellation %s: initial %.1f dB, final %.1f dB, reached -20 dB after %.0f ms" \
			% [echo_kind, initial_attenuation_db, final_attenuation_db, adaptation_ms])
	if first_20_db_frame == -1:
		push_error("Echo cancellation %s case never reached %.1f dB" % [echo_kind, REQUIRED_ATTENUATION_DB])
		return false
	if final_attenuation_db > REQUIRED_ATTENUATION_DB:
		push_error("Echo cancellation %s case ended at only %.1f dB" % [echo_kind, final_attenuation_db])
		return false
	if final_attenuation_db > initial_attenuation_db - REQUIRED_IMPROVEMENT_DB:
		push_error("Echo cancellation %s case did not measurably adapt" % echo_kind)
		return false
	return true


func _initialize() -> void:
	if not ClassDB.class_exists("TwoVoipEchoCanceler"):
		push_error("Echo cancellation smoke test: TwoVoipEchoCanceler is not registered")
		quit(1)
		return

	var passed := true
	for echo_kind in ["identical", "scaled", "room"]:
		passed = run_echo_case(echo_kind) and passed
	if passed:
		print("TwoVoIP echo cancellation smoke test passed")
	quit(0 if passed else 1)
