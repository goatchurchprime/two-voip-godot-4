## Description

Welcome to the GodotEngine GDExtension [TwovVoip](https://store.godotengine.org/asset/goatchurch/twovoip/) designed 
to cater to all your VoIP (Voice Over IP) needs when building networked games in Godot.

This plugin uses the industry standard [Xiph/Opus](https://github.com/xiph/opus) compression library 
and the [Xiph/RNNoise](https://github.com/xiph/rnnoise) de-noiser all wrapped in an easy-to-integrate voiphelper 
component to help you get your game players speaking to one another over the network in minutes.

Thanks to [@ajlennon](https://github.com/ajlennon) and [@DmitriySalnikov](https://github.com/DmitriySalnikov) 
for work on the github actions that are successfully building this plugin across 
[all six](https://docs.godotengine.org/en/stable/about/list_of_features.html#platforms) GodotEngine supported platforms.

## High level demo

<img align="right" width="304" height="569" alt="image" src="https://github.com/user-attachments/assets/2a246073-4b88-4008-9390-6ee93422e045" />
An HTML5 demo is hosted at https://goatchurch.itch.io/twovoip-mqtt

The purpose of this demo is to test all the features so you can hear what the opus compression and noise cancelling settings do to a voice recording, as well as debug sample rate issues.

1. Clone/Download this repository.
2. Open the project in the `example/` directory in Godot 4.6.
3. Go to assetstore, search for twovoip, and install it.
4. Run the main scene `radiomqtt.tscn`. 
5. If the microphone is working, then you should see a waveform in the app like this:

Use the [mic_record](https://github.com/godotengine/godot-demo-projects/tree/master/audio/mic_record) demo project
to resolve issues only to do with the microphone.

#### Top panel

This controls the microphone and sound output device.  The microphone is working when the "Mic Enabled" button is green, and it is recording and transmitting when the "PTT" (Press to Talk) button is pressed.  The "Vox" button will make the PTT voice activated, which means it turns on when sound goes above a certain threshold controlled by the size of the pink area on the blue sound visualizer area.

The "De-Noise" button enables the RNNoise filter.  You can turn it on and off and play back the same clip to hear what difference it makes.

#### LibOpus compression and resampling panel

This section allows you to control all the parameters in that operate the Opus compression library, such as the Frame duration (settings between 2.5ms and 60ms), the Bit rate (bandwidth target), Sample rate, Compression Complexity, if it records stereo and if it is optimized for voice.

Each time you change one of these values, or toggle the De-Noise setting, the original sound recording from the microphone is reprocessed.  This lets you experience how the quality of the sound and band-width changes for the different settings.

#### Recording playback panel

This section has the "Play" button to decode and play back the most recent recorded sample, and it displays how many packets and bytes would have been transmitted for this clip.

#### MQTT transmission

Finally, there is an MQTT transmission section to push audio packets over the network via a broker on a topic.  Click the \[Connect\] button to go online while a friend does the same on another computer and you should be able to talk to one another over the internet (don't forget to use the PTT button or enable VoX).  Several presets are given for convenience, and it will automatically use websockets if you are operating from HTML5.

MQTT is a lightweight protocol implemented in another GodotEngine GDExtension [https://godotengine.org/asset-library/asset/1993](godot-mqtt) and described [here](https://github.com/goatchurchprime/godot-mqtt/?tab=readme-ov-file#mqtt). Its publish, subscribe, retained and last will messaging system provides an effective framework for tracking the joining state of each player.  There is a line of text beginning with `mosquitto_sub` command that you can copy into your terminal window to watch the data fly by. 

There is a fuzzing system to degrade the data and a logging system so you can record and replay an episode of packets.

The table of users shows who is connected to this broker and whether they are transmitting.

The "T" button for each user replaces the incoming audio data after it is unpacked with a pure 440Hz tone.  This feature is to help discriminate the nature of broken up audio as to whether it is due to gaps between the incoming packets as it is played back, or just bad audio being transmitted in the first place.

## Using the voiphelper

You are recommended to use the `voiphelper` module rather than implement your VoIP system from the
core `opus` and `rnnoise` components because it has the necessary features of Vox gating (Voice activation), 
jitter buffers, packet re-ordering (in case of unreliable transmition) and dynamic lag management.

The speech is sent as binary streams of opus packets with a two byte header to number the packet with
JSON encoded headers and footers to assist with reliability and debugging.

The parameters of the header are `{ opusframesize, opussamplerate, opuschannels, lenchunkprefix, opusstreamcount, opusframecount, talkingtimestart }` and the parameters of the footer are `{ opusstreamcount, opusframecount, talkingtimeduration, talkingtimeend }`.

As mentioned above `lenchunkprefix=2`. Also, `opusstreamcount` increments with each stream to give it a unique id,
and `opusframecount=0` in the header.  If a player joins the network while one someone is talking mid-stream,
then `request_audio_json_packet_mid_header()` will prove a header object with the correct value in `opusframecount`.

### simpleexample

This module contains the minimal wrapper for the `TwoVoipMic` and `TwoVoipSpeaker` modules of `voiphelper`.

#### Input player

The function `$TwoVoipMic.init_voip_mic()` takes seven parameters.  The first parameter is `json_packets_as_binary` which means that
that the values that would have been emitted to the signal `transmit_audio_json_packet` are stringified and emitted to
`transmit_audio_packet`.  This simplifies the library, but removes the ability to easily intercept the json headers and footers
and use the data in them.

The next four parameters are optional buttons `MicOn`, `PTT`, `Vox`, `Denoise` that you can choose to share from the user interface in your game.
The sixth parameter `InputOption` is of type [OptionButton](https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#optionbutton) and is populated with the results of
[AudioServer.get_input_device_list()](https://docs.godotengine.org/en/stable/classes/class_audioserver.html#class-audioserver-method-get-input-device-list).
Finally there is the `voxshader.gdshader` material you can use to make an activity waveform.

The the opus encoder itself is created by `set_opus_values(opussamplerate, opusframedurationms, channels, opusbitrate, opuscomplexity, opusoptimizeforvoice)` where `opussamplerate` is chosen from [48000, 24000, 12000, 8000],
`opusframedurationms` which must be one of [5, 10, 20, 40, 60], `channels` is 1 for mono and 2 for stereo,
`opusbitrate` is a range between 500 and 64000, `opuscomplexity` a number between 1 and 10, `opusoptimizeforvoice` a boolean value.  These are better outlined in the [Opus Definition](https://datatracker.ietf.org/doc/html/rfc6716#section-2.1).

If the `Vox` option is set, then `TwoVoipMic.set_voxthreshhold(voxthreshhold)` will set the gating threshold threshold
(this sets the visual parameter in the shader).  There is also `hangtime` the time the microphone will
keep running after the noise has fallen below the voxthreshold, and `leadtime` [FIXME: not implemented]
the amount of time that is captured from
the buffer before the threshold was reached to avoid clipping.

#### Output player

The `TwoVoipSpeaker` module handles incoming VoIP packets in the function 
`receive_audio_packet(packet)` and manages an `AudioStreamOpus` object loaded into an `AudioStreamPlayer`.

The packets are either raw opus chunks or json-encoded header or footer.  The function `external_end_stream()`
will auto-generate an end stream if one is missing because the network has been interrupted so that it doesn't
try to retain the buffers.

The `TwoVoipSpeaker` has two important settings, `audio_buffer_lag_time_target` and `audio_buffer_lag_time_target_tolerance`
that set a target buffer size in seconds and is responsible for the audio delay
that makes sure there are no gaps in the playback when packets get delayed by up to the lag time target.
The buffer is maintained by pausing the playback until the target is reached,
of speeding up the playback when the lag buffer has increased by more than the tolerance, which
can happen if an individual packet is held back a long time and not skipped or the game stalls, such as when
it is compiling shaders.

Obviously the system needs to know when a stream has ended (a footer has been received) so it can consume the buffer down to zero.

The `set_sinewave_out()` setting replaces the audio as it is decoded with a 440Hz tone so it's possible
to tell the difference between choppy transmission and playing and a choppy microphone data.
Use `get_chunk_max()` to get an indicator of the audio coming from a particular player, which helps
to tell the difference between whether they are muted, or your playback volume has been turned down.

### Low-level encoder processing

The low-level encoder can keep its output frame size as configuration, leaving
the per-frame processing call concerned only with audio. For a 20 ms Opus frame
at 48 kHz:

```gdscript
var encoder := TwovoipOpusEncoder.new()
var error := encoder.create_sampler(
    AudioServer.get_input_mix_rate(),
    48000,
    2,
    TwovoipOpusEncoder.DENOISER_DISABLED,
    TwovoipOpusEncoder.AGC_DISABLED,
    960,
)
assert(error == OK)
encoder.create_opus_encoder(12000, 5, true)

var required := encoder.get_required_input_chunk_size()
var frames := AudioServer.get_input_frames(required)
var consumed := encoder.process_chunk(frames)
if consumed >= 0:
    var peak := encoder.get_peak()
    var rms := encoder.get_rms()
    var packet := encoder.encode_chunk()
```

`get_required_input_chunk_size()` is constant until the sampler is reconfigured.
It is the ceiling of the input/output sample ratio, and is
therefore conservative for fractional combinations. `process_chunk()` rejects
a shorter array without advancing processing state and returns the number of
input frames actually consumed. The Speex filter state and output capacity can
occasionally leave additional frames unconsumed, particularly on the first
call for some rate and long-frame combinations. The caller must retain
`frames.size() - consumed` frames; TwoVoIP does not buffer or discard them.

`set_gain()` and `get_gain()` control a manual linear amplitude multiplier. It
is applied after voice preprocessing and remains independent of automatic gain.
For mono voice, pass `AGC_APPLIED` to `create_sampler()`; Speex then performs
its native in-place AGC. `get_agc_gain()` reports Speex's
latest gain for diagnostics, but TwoVoIP does not attempt to set or reproduce
Speex's internal gain behavior.

The denoiser is selected in `create_sampler()`. Speex denoise
works through the same mono preprocessor state as AGC. RNNoise requires mono
48 kHz audio and chunks divisible by its 480-sample (10 ms) frame. A core-only
build returns `ERR_UNAVAILABLE` when RNNoise is selected; it never pretends that
noise suppression succeeded. Stereo is left as a manual-gain music path. Voice
preprocessing modes are immutable sampler configuration. Call
`create_sampler()` again to begin a stream with different settings.

Speex preprocessing uses 10 or 20 ms internal frames, so the output chunk must
divide into one of those durations. Shorter Opus frames remain available when
voice preprocessing is disabled.

The older `set_output_chunk_size()`, `calc_audio_chunk_size()`, and
`process_pre_encoded_chunk()` calls are
deprecated but retained for compatibility. They issue one warning per encoder
object and use the same processing implementation.

#### Networking layer

In the `transmit_audio_json_packet=true` mode the `TwoVoipMic` module outputs all its data via the signal
`transmit_audio_packet(opuspacket)` which needs to be sent to the `receive_audio_packet(packet)` for each player.

When a player joins mid-stream use `TwoVoipMic.request_audio_json_packet_mid_header()` to create an intermediate
header for them so that they know how to decode the opus packets.

## Building the addon

There are four submodules in this repository.

**godot-cpp** is contains the header files and class definitions required to build a compiled 
[GDExtension](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html) object that can 
dynamically link to the GodotEngine at runtime.
TwoVoip 6.1 pins the submodule to the official `godot-cpp` `10.0.0-rc1`
release (`58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74`), whose generated API is
Godot `4.6-stable`. The godot-cpp project changed its release numbering after
its `godot-4.5-stable` release, so the `10.0.0-rc1` name refers to the binding
library version rather than a Godot 4.6 release candidate.

**opus** is the opus voice compression and decompression library from [xiph.org](https://xiph.org/) that 
generally takes an array of 960 pairs of floats representing 20ms of stereo audio samples at 48kHz and 
returns 20 to 30 bytes of compressed data for that chunk.

**speexdsp** is a direct submodule of the official
[Xiph SpeexDSP repository](https://github.com/xiph/speexdsp), pinned to the
signed `SpeexDSP-1.2.1` release at commit
`1b28a0f61bc31162979e1f26f3981fc3637095c8`. TwoVoIP compiles the resampler and
preprocessor sources directly into the extension. This is the same upstream resampler
revision that was previously copied into `src`, with its floating-point mode
selected explicitly by the build.

**rnnoise** is a direct submodule of the official
[Xiph RNNoise repository](https://github.com/xiph/rnnoise), pinned to commit
`372f7b4b76cde4ca1ec4605353dd17898a99de38`. Xiph does not provide CMake build
files at that revision, so TwoVoIP supplies a small CMake adapter in
`thirdparty/rnnoise`. RNNoise also keeps its large default model outside Git;
the adapter downloads model revision `0b50c45` from Xiph and verifies its
SHA-256 checksum before compiling it.

The sequence of commands to build the system locally on NixOS are:
```bash
nix-shell -p scons cmake ninja autoreconfHook
scons apply_patches  # apply the pinned portability and size patches
scons build_opus     # build opus using cmake
scons build_rnnoise  # build RNNoise using cmake
scons                # build this library
cp addons/twovoip/libs/*.so example/addons/twovoip/libs/
```
