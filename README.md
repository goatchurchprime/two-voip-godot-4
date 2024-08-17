## Demo instructions
1. Clone/Download this project and open in Godot.
2. Go to assetlib and search for twovoip, and install it.
3. Run the app try making and playing recordings (don't forget to hold down PTT) or MQTT-connecting at the same time as someone else.

4. If the microphone is working, then you should see a waveform on the app like this:
![image](https://github.com/user-attachments/assets/6571635a-a134-4efb-862b-9e62f04854d6)

If there's no response on MacOS, it could be [this issue](https://github.com/quellus/GDTuber/issues/76)  Go to Project Settings (with Advanced Settings selected) -> Audio -> Driver -> Mix rate and set to 48000


## Opus compression audio for Godot

This is a low level operation of the opus library based on https://github.com/RevoluPowered/one-voip-godot-4/
with a VoIP-over-MQTT demo project.  

It can also integrate with [OVRLipSync](https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/) 
if you download it and are not on Linux.

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

```bash
git clone git@github.com:xiph/rnnoise.git
cd rnnoise
nix-shell -p autoreconfHook
./autogen.sh    # this will download 47Mb trained model data
./configure
make
```
