# WebRTC conditioner

`TwoVoipWebRTCConditioner` owns one WebRTC Audio Processing Module instance. AEC3,
noise suppression and gain control can be enabled independently.

```gdscript
var conditioner := TwoVoipWebRTCConditioner.new()
conditioner.initialize(chunk_ms, input_mix_rate, opus_sample_rate, channels)
conditioner.set_stream_delay_ms(render_to_capture_delay_ms)
var microphone_frames := AudioServer.get_input_frames(conditioner.get_input_chunk_size())
var opus_rate_frames := conditioner.condition(microphone_frames, render_frames)
assert(opus_rate_frames.size() == conditioner.get_output_chunk_size())
```

Input and render arrays are native-rate stereo frames. `channels` selects mono
or stereo processing; mono output is duplicated into both sides of each returned
`Vector2`. `chunk_ms` must be a
multiple of 10 ms. WebRTC returns the same duration at the requested
output rate, ready to pass to the Opus encoder. The delay setter deliberately
supplies an external estimate to WebRTC; `get_stream_delay_ms()` returns the
echo canceller's measured delay instead of echoing that setting.

The initial integration is optional and Linux development-only. Build it with:

```bash
scons build_dependencies platform=linux arch=x86_64 target=template_debug
scons platform=linux arch=x86_64 target=template_debug
godot4 --headless --path . --script res://tests/conditioner_smoke.gd
```
