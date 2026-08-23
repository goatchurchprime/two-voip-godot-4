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

MQTT is a lightweight protocol implemented in another GodotEngine GDExtension [https://godotengine.org/asset-library/asset/1993](godot-mqtt) and described [here](https://github.com/goatchurchprime/godot-mqtt/?tab=readme-ov-file#mqtt). Its publish, subscribe, retained and last will messaging system provides an effective framework for tracking the joining state of each player.  There is a line of text beginning with `mosquitto_sub` command that you can copy into your terminal window to watch the data fly by. 

There is a fuzzing system to degrade the data and a logging system so you can record and replay an episode of packets.

The table of users shows who is connected to this broker and whether they are transmitting.

The "T" button for each user replaces the incoming audio data after it is unpacked with a pure 440Hz tone.  This feature is to help discriminate the nature of broken up audio as to whether it is due to gaps between the incoming packets as it is played back, or just bad audio being transmitted in the first place.

## Using the voiphelper

You are recommended to use the voiphelper module rather than implement your VoIP system directly from the
core opus and rnnoise components as you will merely be re-implementing its functionality of
packet reordering, jitter buffers, and dynamic lag estimation.
It takes a lot of developer time to get all of this running smoothly and 
taking advantage of low latency unreliable channels of some network systems.

### simpleexample

This module contains the minimal wrapper for the `TwoVoipMic` and `TwoVoipSpeaker` modules of `voiphelper`.

#### Input player

The `TwoVoipMic` module needs to be connected to the buttons `MicOn`, `PTT`, `Vox`, `Denoise` and an `InputOption` of type [OptionButton](https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#optionbutton) that gets populated with the results of 
[AudioServer.get_input_device_list()](https://docs.godotengine.org/en/stable/classes/class_audioserver.html#class-audioserver-method-get-input-device-list).  These are optional.  If you don't give it a reference to a button then that feature won't be available.

The other parameters are set by `setopusvalues()`:
 * `opussamplerate` is chosen from [48000, 24000, 12000, 8000]
 * `opusframedurationms` which must be one of [5, 10, 20, 40, 60]
 * `channels` is 1 for mono and 2 for stereo
 * `opusbitrate` a range between 500 and 64000
 * `opuscomplexity` a number between 1 and 10
 * `opusoptimizeforvoice` a boolean value

Pass in a shader material based on `voxshader.gdshader` as the final parameter to create a visual preview of the noise from
the microphone.

If the `Vox` option is set, then `TwoVoipMic.set_voxthreshhold(voxthreshhold)` will set the gating threshold threshold
(this sets the visual parameter in the shader).  Also in the module are `hangtime` the time the microphone will
keep running after the noise has fallen below the voxthreshold, and `leadtime` the time before the theshold was 
reached that is captured.

To be implemented: microphone_gain = 1.0

#### Output player

The `TwoVoipSpeaker` module handles incoming voip packets in the function 
`tv_incomingaudiopacket(packet)` and manages an `AudioStreamOpus` object the given `AudioStreamPlayer`.

The packets are either a raw opus chunk that will be unpacked by the opus library, or a header or footer json object:

Header parameters:

 * opusframesize  
 * opussamplerate 
 * opuschannels
 * lenchunkprefix is usually 2 bytes for a counter used to detect missing or out of order packets if transmitted unreliably 
 * opusstreamcount 
 * opusframecount
 * talkingtimestart

Footer parameters:
 * opusstreamcount
 * opusframecount
 * talkingtimeduration
 * talkingtimeend

#### Networking layer

The `TwoVoipMic` module outputs its data via two signals:

 * transmitaudiojsonpacket - a JSON header or footer
 * transmitaudiopacket - a packed opus packet

Both sets of data (the former stringified into the latter) need to be sent to the `TwoVoipSpeaker.tv_incomingaudiopacket(packet)`
function for each of the networked players.

The reason for the implementation by two functions is so that the network layer can insert an intermediate header 
for the middle of a stream for when a new player joins when one of the players is talking.

## Building the addon

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
