# WebRTC conditioner

`TwoVoipConditioner` owns one WebRTC Audio Processing Module instance. It is a
separate class from `TwoVoipEchoCanceler`; it does not select between backends.
This initial integration enables AEC3 only so its echo cancellation can be
evaluated in isolation. Noise suppression and gain control remain disabled.

```gdscript
var conditioner := TwoVoipConditioner.new()
conditioner.initialize(input_mix_rate, opus_sample_rate, input_chunk_size)
conditioner.set_stream_delay_ms(render_to_capture_delay_ms)
var opus_rate_frames := conditioner.condition(microphone_frames, render_frames)
```

Input and render arrays are native-rate stereo frames. The input chunk must
contain whole 10 ms frames. WebRTC returns the same duration at the requested
output rate, ready to pass to the Opus encoder. The delay setter deliberately
has no getter: it supplies an external estimate to WebRTC and is not a measured
result from the echo canceller.

The initial integration is optional and Linux development-only. Build it with:

```bash
scons build_dependencies platform=linux arch=x86_64 target=template_debug
scons platform=linux arch=x86_64 target=template_debug
godot4 --headless --path . --script res://tests/conditioner_smoke.gd
```
