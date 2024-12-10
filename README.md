## Description

Welcome to the GodotEngine GDExtension [twovoip](https://godotengine.org/asset-library/asset/3169) 
that applies the [xiph/opus](https://github.com/xiph/opus) compression library 
(and optionally the [xiph/rnnoise](https://github.com/xiph/rnnoise) de-noiser and 
[OVRLipSync](https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/) viseme detector)
to an audio stream of speech from the microphone. 
The starting point for this project was [one-voip-godot-4](https://github.com/RevoluPowered/one-voip-godot-4/).

Thanks to [@ajlennon](https://github.com/ajlennon) and [@DmitriySalnikov](https://github.com/DmitriySalnikov) 
for indefatiguable work on the github actions that are successfully building this plugin across 
[all six](https://docs.godotengine.org/en/stable/about/list_of_features.html#platforms) GodotEngine supported platforms.

## Demo example

An HTML5 demo is hosted at https://goatchurch.itch.io/twovoip-mqtt

The purpose of this demo is to test all the features so you can hear what the opus compression and noise cancelling settings do to a voice recording, as well as debug sample rate issues.

1. Clone/Download this repository and open the project in the `example/` directory in Godot 4.3.
2. Go to assetlib, search for twovoip, and install it.  (Now on version 3.3)
3. Run the app. 
4. If the microphone is working, then you should see a waveform in the app like this:

![image](https://github.com/user-attachments/assets/6571635a-a134-4efb-862b-9e62f04854d6)

If there is no response on MacOS, it could be [this issue](https://github.com/quellus/GDTuber/issues/76)  
Go to Project Settings (with Advanced Settings selected) -> Audio -> Driver -> Mix rate and set to 48000

The top section of the user interface has the PTT (Press to Talk) button and Vox button (Voice Activity Detection) where the 
activation threshold is given in the slider below it (on top of the waveform). 
Click on \[De-noise\] to hear how recordings 
sound with and without this feature.

#### A Note about the sample rates
There are two different `mix_rates` values in the GodotEngine that vary according to platform:  
* [audio/driver/mix_rate](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-audio-driver-mix-rate) is available in the ProjectSettings and can be overridden for different platforms
* [AudioServer.mix_rate](https://docs.godotengine.org/en/stable/classes/class_audioserver.html#class-audioserver-method-get-mix-rate) is set by the platform

Additionally, an `AudioStream` can have its own `mix_rate`, and the resampling ratio that is applied internally on the data in the stream will be `target_mix_rate/(AudioStream.mix_rate*AudioStreamPlayer.pitch_scale)`.

All combinations are exposed in the `TwoVoip` plugin and the example project to help you work out what settings are correct.  If you record and playback on the same system then wrong settings can cancel out and make it appear that a bad signal between different systems is due to the transmission.  The common problems are playing a 48KHz stream at 44.1KHz which will sound slow and off-key, or playing a decoded 44.1KHz stream from a network at 48KHz which will result in small gaps between the packets that are being consumed too fast and can sound like analog radio static distortion (which is impossible).

Because the Opus Compression and RNNoise libraries only work at certain sample rates (none of which are 44.1KHz) the `AudioEffectOpusChunked` class has an internal resampler, though this could have been implemented by setting the `pitch_scale` to 0.91875=44100/48000.  Similarly on the output the `AudioStreamOpusChunked` class also has a resampler that could be made redundant by tinkering with the `pitch_scale` and `mix_rate`.  The properties of these classes are controlled by the frame size and sample rate instead of sample time to make it clear that these all relate to known fixed width arrays of floating point values.  In fact the entire library can operate independently of the audio system and just on these Packed Arrays.

![image](https://github.com/user-attachments/assets/4928a06c-15c2-4e9e-a71c-d2de26d03856)

This section controls all the settings for the Opus compression in terms of frame duration, sample rate and bit rate.  The purpose of the resampler definition on the middle line is match the sample rate told to the Opus compression library.  

![image](https://github.com/user-attachments/assets/f67438c5-75f9-44ef-9b0a-69f0ac8cfaeb)

Use the \[Play\] button in the Recording Playback section to hear up to 10 seconds of the last recording you made 
by holding down the PTT (either manually or automatically by the Vox).  The Bytes per second for the audio 
compression is shown here and is recalculated from the uncompressed recording whenever you change the Opus settings. 

![image](https://github.com/user-attachments/assets/f5d4db27-edb2-466f-b056-24423bad08c8)

Finally, there is an MQTT transmission section to push audio packets over the network via a broker on a topic.  Click the \[Connect\] button to go online while a friend does the same on another computer and you should be able to talk to one another over the internet (don't forget to use the PTT button).  Several presets are given for convenience, and it will automatically use websockets if you are operating from HTML5.

MQTT is a lightweight protocol implemented in another GodotEngine GDExtension [https://godotengine.org/asset-library/asset/1993](godot-mqtt) and described [here](https://github.com/goatchurchprime/godot-mqtt/?tab=readme-ov-file#mqtt). Its publish and subscribe, and retained and last will messages system provides a simple basis for each player track who is joining or leaving the network.  There is a line of text beginning with `mosquitto_sub` command that you can copy into your terminal window to watch the data fly by. 


## Minimal Use Case

If you are familiar with the [Godot Audio system](https://docs.godotengine.org/en/stable/tutorials/audio/index.html), the following minimal use case of this plugin should make sense:

As outlined in the [docs](https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html), 
create an `AudioStreamPlayer` with `stream=AudioStreamMicrophone`, set it to Autoplay, and 
ensure your ProjectSettings have `audio/driver/enable_input` set to true.
Set its bus to a new bus called "MicrophoneBus" which should be Muted to 
stop it creating a feedback loop to the output.  Add an effect 
`OpusChunked` to the MicrophoneBus.  This will only be an option if the `twovoip` addon is installed.

Assuming that `AudioEffectOpusChunked` is the first one on the bus, you can get a reference to it with
```GDScript
var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
var opuschunked : AudioEffectOpusChunked = AudioServer.get_bus_effect(microphoneidx, 0)
```

Now you can consume and transmit the byte chunks with the following code:
```GDScript
func _process(delta):
    var prepend = PackedByteArray()
    while opuschunked.chunk_available():
        var opusdata : PackedByteArray = opuschunked.read_opus_packet(prepend)
        opuschunked.drop_chunk()
        transmit(opusdata)
```

At the other end you can decode the opus packets into an `AudioStreamPlayer` whose 
stream is set to an `AudioStreamOpusChunked`.

```GDScript
var audiostreamopuschunked : AudioStreamOpusChunked = $AudioStreamPlayer.stream
var opuspacketsbuffer = [ ]   # append incoming packets to this list
func _process(delta):
    while audiostreamopuschunked.chunk_space_available():
        audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), 0, 0)
```

Opus packets don't have any context, so if you want to number them so they can be shuffled 
if they get out of order in the particular network data channel you are using, you can use the `prepend` 
array to splice an index value into a header.
Then `prefixbyteslength` needs to be the same length as this header so it can be split off 
on its way to the decoder.
The forward error correction flag, `fec`, can be set to 1 if the previous packet is missing.
 
If you want to attach only native Godot classes to the audio busses and audio streams 
you can do the same thing as above 
using the corresponding `AudioEffectCapture` and `AudioStreamGeneratorPlayback` object to 
handle the audio chunks in the form of
`PackerVector2Array`s while running these two external classes in isolation, like 
`audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, audiosamples, denoise)`
and:
```GDScript
var audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
while audiostreamgeneratorplayback.get_frames_available() > audiostreamopuschunked.audiosamplesize:
    var audiochunk = audiostreamopuschunked.opus_packet_to_chunk(opuspacketsbuffer.pop_front(), prefixbyteslength, fec)
    audiostreamgeneratorplayback.push_buffer(audiochunk)
    audiostreamgeneratorplayback.push_buffer(audiopacketsbuffer.pop_front())
```

The `chunk_max()` function is for implementing a Vox (Voice Activity Detection) feature 
so that you can save processor cycles by dropping chunks before you opus encoding them. 
Or you can use `denoise_resampled_chunk()` (which requires resampling to 48kHz) to read a 
speech probability, or optionally measure `chunk_max()` post de-noising.

The opus compression and denoiser features need the chunks to be sent to them in order 
because they use the state recorded from earlier audio samples to provide context and improve the performance 
of the current chunk.  Use `flush_opus_encoder()` if you anticipate a gap from the previous chunk 
(eg the PTT was off for a period and there was no processing).
The `undrop_chunk()` function can roll back the chunk buffer and by some milliseconds 
so you can avoid clipping at the start of a speech sequence.

## Build structure

There are three submodules in this repository.  

**godot-cpp** is contains the header files and class definitions required to build a compiled 
[GDExtension](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html) object that can 
dynamically link to the GodotEngine at runtime.

**opus** is the opus voice compression and decompression library from [xiph.org](https://xiph.org/) that 
generally takes an array of 960 pairs of floats representing 20ms of stereo audio samples at 48kHz and 
returns 20 to 30 bytes of compressed data for that chunk.

**noise-suppression-for-voice** contains a copy of the [xiph/rnnoise](https://github.com/xiph/rnnoise) 
code in its external/rnnoise directory with the all important `CMakeLists.txt` file that makes it possible 
to compile it on all the diffeerent platforms

The sequence of commands to build the system locally
```bash
nix-shell -p scons cmake ninja autoreconfHook # if you are on nix
scons apply_patches  # optional
scons build_opus     # build opus using cmake
scons build_rnnoise  # build opus using cmake
scons                # build this library
cp addons/twovoip/libs/*.so example/addons/twovoip/libs/
```

To compile for another platform like web, the commands are
```bash
scons apply_patches
scons platform=web target=template_release build_opus
scons platform=web target=template_release build_rnnoise
scons platform=web target=template_release
```

## With OVRLipSync

This is a highly speculative component that takes advantage of the chunking feature in the OpusChunked effect,
but which is currently closed source and distributed as a library only for Windows, Android and Mac.
There is [no Linux version](https://github.com/godotengine/godot-proposals/discussions/9718).
The github actions compiles a version for the available platforms 
with `scons lipsync=yes` and creates an `addons/twovoip_lipsync` that can be copied into a project

Download the OVRLipSync libraries from https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/
and unzip into top level as OVRLipSyncNative directory in this project.  There is a stub include file
for Linux that allows this GDExtension to compile without this library.

On Windows you may need to copy the `OVRLipSyncNative/Lib/Win64/OVRLipSync.dll` file to the same directory
as your `GodotEngine.exe` so that it finds and links it.

For the addon to work correctly, `twovoip_lipsync` and `twovoip` cannot be used in the same project.


### Nixos automated (not working)

The build system is defined by the flake.nix file

 * makes a result directory that needs to be copied into addons

```
nix build
cp result/addons/twovoip/*so addons/twovoip
```

 * android version:

```
nix build .#android
cp result/addons/twovoip/*so addons/twovoip
```

On Windows:

Use Visual Studio 2022 Community Edition with CMake option to open opus
directory and convert cmake script to sln and then compile.

```
cd ../..
python -m SCons
```
