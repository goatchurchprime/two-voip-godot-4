## Description

Welcome to the GodotEngine GDExtension [twovoip](https://store.godotengine.org/asset/goatchurch/twovoip/) designed 
to cater to all your VoIP (Voice Over IP) needs when building networked games in Godot.

This plugin uses the industry standard [xiph/opus](https://github.com/xiph/opus) compression library 
and the [xiph/rnnoise](https://github.com/xiph/rnnoise) de-noiser all wrapped in an easy-to-integrate voiphelper 
component to enable you to get your game players speaking to one another over the network in minutes.

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


The top panel controls the microphone and sound output device.  The microphone is working when the "Mic Enabled" button is green, and it is recording and transmitting when the "PTT" (Press to Talk) button is pressed.  The "Vox" button will make the PTT voice activated, which means it turns on when sound goes above a certain threshold, which is set by the pink area on the blue sound visualizer area.

The "De-Noise" button enables the RNNoise filter.  You can turn it on and off and play back the same clip to hear what difference it makes.

#### LibOpus compression and resampling

This section allows you to control all the parameters in that operate the Opus compression library, such as the Frame duration (settings between 2.5ms and 60ms), the Bit rate (bandwidth target), Sample rate, Compression Complexity, if it records stereo and if it is optimized for voice.

Each time you change one of these values, or the toggle the De-Noise setting, the original sound recording from the microphone is reprocessed.  This lets you hear how the quality of the sound and see how band-width changes for the different settings.

#### Recording playback

This section has the "Play" button to decode and play back the most recent recorded sample, and it displays how many packets and bytes would have been transmitted for this clip.

#### MQTT transmission

Finally, there is an MQTT transmission section to push audio packets over the network via a broker on a topic.  Click the \[Connect\] button to go online while a friend does the same on another computer and you should be able to talk to one another over the internet (don't forget to use the PTT button).  Several presets are given for convenience, and it will automatically use websockets if you are operating from HTML5.

MQTT is a lightweight protocol implemented in another GodotEngine GDExtension [https://godotengine.org/asset-library/asset/1993](godot-mqtt) and described [here](https://github.com/goatchurchprime/godot-mqtt/?tab=readme-ov-file#mqtt). Its publish and subscribe, and retained and last will messages system provides a simple basis for each player track who is joining or leaving the network.  There is a line of text beginning with `mosquitto_sub` command that you can copy into your terminal window to watch the data fly by. 

There is a fuzzing system to degrade the data and a logging system so you can record and replay an episode of packets.

The table of users shows who is connected to this broker and whether they are transmitting.

The "T" button for each user replaces the incoming audio data after it is unpacked with a pure 440Hz tone.  This feature is to help discriminate the nature of broken up audio as to whether it is due to gaps between the incoming packets as it is played back, or just bad audio being transmitted in the first place.


## Using the voiphelper

You are recommended to use the voiphelper module rather than implement your voip system directly from the 
core opus and rnnoise components as you will merely be re-implementing its functionality of 
packet reordering, jitter buffers, and dynamic lag estimation.  It's an art to get all of this running 
smoothly against all the glitches that you get from a network system, and it's better if we all share the same 
system that can be progressively improved, rather than do our own thing with what is not actually a very interesting problem.

-----------
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
