## Description

Welcome to the GodotEngine GDExtension [twovoip](https://godotengine.org/asset-library/asset/3169) 
that applies the [xiph/opus](https://github.com/xiph/opus) compression library 
(and optionally the [xiph/rnnoise](https://github.com/xiph/rnnoise) de-noiser and 
[OVRLipSync](https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/) viseme detector)
to an audio stream of speech from the microphone.

## Demo example instructions

1. Clone/Download this project and open in Godot 4.3.
2. Go to assetlib, search for twovoip, and install it.
3. Run the app. 
4. If the microphone is working, then you should see a waveform on the app like this:
![image](https://github.com/user-attachments/assets/6571635a-a134-4efb-862b-9e62f04854d6)

If there is no response on MacOS, it could be [this issue](https://github.com/quellus/GDTuber/issues/76)  
Go to Project Settings (with Advanced Settings selected) -> Audio -> Driver -> Mix rate and set to 48000

The top section of the user interface has the PTT (Press to Talk) button and Vox button (Voice Activity Detection) where the 
activation threshold is given in the slider below it.  Click on \[De-noise\] to hear how recordings 
sound with and without this feature.

Use the \[Play\] button in the Recording Playback section to hear up to 10 seconds of the last recording you made 
by holding down the PTT (either manually or automatically by the Vox).  The Bytes per second for the audio 
compression is shown here.

The LibOpus compression and resampling section has options for altering the frame size and compression rate 
on the recorded sample before you play it back so you can experiment with how it sounds with different settings.
Since the internal Godot audio sample rate of 44.1kHz doesn't match the 48kHz that the Opus and RNNoise libraries 
are designed for, a function copied from the Speex codebase resamples it to the higher sample rate.
If you are curious about what how much difference this 8% change in the sample rate makes, 
you can experiment with the "44.1kHz as 48kH" option.  
  
Finally, there is an MQTT transmission section for you to publish audio packets over the network via a 
a broker on a topic.  Click the \[Connect\] button to go online while a friend does the same on another computer and you 
should be able to talk to one another over the internet (don't forget to use the PTT button).
Several presets are given for convenience, and it will automatically use websockets if you are operating from HTML5.

MQTT is a lightweight protocol 
implemented in another GodotEngine GDExtension [https://godotengine.org/asset-library/asset/1993](godot-mqtt)
and described [here](https://github.com/goatchurchprime/godot-mqtt/?tab=readme-ov-file#mqtt).
Its publish and subscribe, and retained and last will messages system provides a simple basis for 
each player track who is joining or leaving the network.  There is some copyable text to 
help you write the `mosquitto_sub` command that logs the messages passing through the server in real time. 


## Minimal Use Case

If you are familiar with the [Godot Audio system](https://docs.godotengine.org/en/stable/tutorials/audio/index.html), the following minimal 
use case of this plugin should make sense:

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
        var opusdata : PackedByteArray = opuschunked.opus_chunk(prepend)
        opuschunked.drop_chunk()
        transmit(opusdata)
```

At the other end you can decode the opus packets into an `AudioStreamPlayer` whose 
stream is set to an `AudioStreamOpusChunked`.

```GDScript
var audiostreamopuschunked : AudioStreamOpusChunked = $AudioStreamPlayer.stream
var opuspacketsbuffer = [ ]   # append incoming packets to this list
var prefixbyteslength = 0
func _process(delta):
    while audiostreamopuschunked.chunk_space_available():
        var fec = 0
        audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), prefixbyteslength, fec)
```

Opus packets don't have any context, so if you want to number them so they can be shuffled if they get out of order 
in the particular network data channel you are using, you can use the `prepend` array to splice in an index values.
Then `prefixbyteslength` needs to be the same length as this header so it can be split off on its way to the decoder.
The forward error correction flag, `fec`, can be set to 1 if the previous packet is missing.
 
If you want to attach only native Godot classes to the audio busses and audio streams you can do the same thing as above 
using the corresponding `AudioEffectCapture` and `AudioStreamGeneratorPlayback` object to handle the audio chunks in the form of
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

Document chunk max, rnnoise and undrop chunk
When a chunk is available you can call the helper functions 
The RNNdenoise is works by calling:
speechnoiseprobability = audioopuschunkedeffect.denoise_resampled_chunk()


## Building on github actions

Thanks to @ajlennon and @DmitriySalnikov without whom this would not be possible.
Notes about the non-portability of rnnoise, but for a secondary project
Notes about compiling locally using scons


## Build instructions:

Only do this locally if you are developing the C++ code.

### Nixos automated

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

### Otherwise by hand when developing

Since we've not got submodules here we need to
first clone Opus and godot-cpp modules before building them

```
git clone --recurse-submodules git@github.com:goatchurchprime/two-voip-godot-4.git
cd two-voip-godot-4
```

On Linux:

```
cd godot-cpp
cmake -Bbuild -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cd build
make
cd ../..
scons
```

**You may need to copy the much simplified `SConstruct_jgtdev` onto `SConstruct` to make it work.  
Also, the project has been moved down into the example directory, so it's a good idea to go 
into the example/addons directory and set up the following symlink:
> ln -s ../../addons/twovoip twovoip


On Windows:

Use Visual Studio 2022 Community Edition with CMake option to open opus
directory and convert cmake script to sln and then compile.

```
cd ../..
python -m SCons
```
On Mac:

See the instructions on the one-voip here: https://github.com/RevoluPowered/one-voip-godot-4/?tab=readme-ov-file#mac



### Using scons

Build a library for the current platform:

```bash
nix-shell -p scons cmake ninja autoreconfHook # if you are on nix
scons apply_patches # optional
scons build_opus # build opus using cmake
scons # build this library
```

Build a library for another platform:

```bash
scons apply_patches # optional
# The scons arguments for build_opus and the build of the library itself must match!
scons platform=web target=template_release build_opus # build opus using cmake
scons platform=web target=template_release # build this library
```

To build with lipsync support, you need to add the `lipsync=yes` flag and download the libraries from the section below.

## With OVRLipSync

This is a highly speculative component that takes advantage of the chunking feature in the OpusChunked effect,
but which is currently closed source.  There is no Linux version.
See https://github.com/godotengine/godot-proposals/discussions/9718

Download the OVRLipSync libraries from https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/
and unzip into top level as OVRLipSyncNative directory in this project.  There is a stub include file
for Linux that allows this GDExtension to compile and work without this library.

On Windows you may need to copy the `OVRLipSyncNative/Lib/Win64/OVRLipSync.dll` file to the same directory
as your `GodotEngine.exe` so that it finds and links it.

For the addon to work correctly, `twovoip_lipsync` and `twovoip` cannot be used in the same project.

## Adding rnnoise

This is a noise supppression library, also from xiph, so it's the best there is.

> nix-shell -p autoreconfHook cmake scons ninja


```bash
git clone git@github.com:xiph/rnnoise.git
cd rnnoise
nix-shell -p autoreconfHook
./autogen.sh    # this will download 47Mb trained model data
./configure
make
```
