## Opus compression audio for Godot

This is a low level operation of the opus library based on https://github.com/RevoluPowered/one-voip-godot-4/
with a VoIP-over-MQTT demo project.  

It can also integrate with [OVRLipSync](https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/) 
if you download it and are not on Linux.

## Build instructions:

### Nixos

The build system is defined by the flake.nix file

 * makes a result directory that needs to be copied into addons
> nix build
> cp result/addons/twovoip/*so addons/twovoip

 * android version:
> nix build .#android
> cp result/addons/twovoip/*so addons/twovoip

Make sure addons/twovoip/twovoip.gdextension point to these files:

### Otherwise by hand when developing

Since we've not got submodules here we need to 
first clone Opus and godot-cpp modules before building them

```
> git clone git@github.com:goatchurchprime/two-voip-godot-4.git
> cd two-voip-godot-4
> git clone git@github.com:godotengine/godot-cpp.git
> cd godot-cpp
> git checkout 48afa82f29354668c12cffaf6a2474dabfd395ed
> cd ..
> git clone git@github.com:xiph/opus.git
> cd opus
> git checkout c85499757c148fede8604cffa12454206b6138ba
> cmake -Bbuild -DCMAKE_POSITION_INDEPENDENT_CODE=ON
> cd build
> make
> cd ../..
> scons  (or python -m SCons on Windows)
```
For MAC see the instructions on the one-voip here: https://github.com/RevoluPowered/one-voip-godot-4/?tab=readme-ov-file#mac

## With OVRLipSync

This is a highly speculative component that takes advantage of the chunking feature in the OpusChunked effect, 
but which is currently closed source.  There is no Linux version.
See https://github.com/godotengine/godot-proposals/discussions/9718

Download the OVRLipSync libraries from https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/ 
and unzip into top level as OVRLipSyncNative directory in this project.  There is a stub include file 
for Linux that allows this GDExtension to compile and work without this library.

On Windows you may need to copy the `OVRLipSyncNative/Lib/Win64/OVRLipSync.dll` file to the same directory 
as your `GodotEngine.exe` so that it finds and links it. 
