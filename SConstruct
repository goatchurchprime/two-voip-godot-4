#!/usr/bin/env python

from SCons.Script import SConscript
from SCons.Script.SConscript import SConsEnvironment

import SCons, SCons.Script
import os, platform
import lib_utils, lib_utils_external

# Fixing the encoding of the console
if platform.system() == "Windows":
    os.system("chcp 65001")

# Project config
project_name = "TwoVoIP"
lib_name = "twovoip"
default_output_dir = os.path.join("addons", "twovoip", "libs")
default_output_lipsync_dir = os.path.join("addons", "twovoip_lipsync", "libs")
src_folder = "src"

# If necessary, add patches from the code
patches_to_apply_rmnoise = [
    "patches/rmnoise-remove-fileio.patch", # Remove fileio from rmnoise library as we get a Windows link error TODO: Work out how to link against the right MSVCRT library
]

patches_to_apply_godot = [
    "patches/godot_cpp_exclude_unused_classes.patch", # Removes unused godot-cpp classes from the build process
    "patches/unity_build.patch", # Speeds up the build by merging the source files. It can increase the size of assemblies.
    "patches/web_threads.patch", # Adds the build flag that appeared in Godot 4.3. Required for a web build compatible with Godot 4.3.
]

print("If you add new source files (e.g. .cpp, .c), do not forget to specify them in 'src/default_sources.json'.\n\tOr add them to 'setup_defines_and_flags' inside 'lib_utils.py '.")
print("To apply git patches, use 'scons apply_patches'.")
print("To build the opus library, use 'scons build_opus'.")

# Additional console arguments
def setup_options(env: SConsEnvironment, arguments):
    from SCons.Variables import Variables, BoolVariable, EnumVariable, PathVariable
    opts = Variables([], arguments)

    # It must be here for lib_utils.py
    opts.Add(PathVariable("addon_output_dir", "Path to the output directory", default_output_dir, PathVariable.PathIsDirCreate))
    opts.Add(PathVariable("ovrlipsync_dir", "Path to the OVRLipSyncNative directory", os.path.join(os.path.dirname(default_output_lipsync_dir), "OVRLipSyncNative"), PathVariable.PathIsDirCreate))

    opts.Add(BoolVariable("lipsync", "Enable lipsync support", False))
    opts.Add(BoolVariable("lto", "Link-time optimization", False))
    opts.Add(BoolVariable("rnnoise", "Enable rnnoise support", True))

    opts.Update(env)
    env.Help(opts.GenerateHelpText(env))


# Additional compilation flags
def setup_defines_and_flags(env: SConsEnvironment, src_out):
    # Add more sources to `src_out` if needed

    if env["lto"]:
        if env.get("is_msvc", False):
            env.AppendUnique(CCFLAGS=["/GL"],
                             ARFLAGS=["/LTCG"],
                             LINKFLAGS=["/LTCG"],)
        else:
            env.AppendUnique(CCFLAGS=["-flto"],
                             LINKFLAGS=["-flto"],)

    env.Append(CPPPATH="opus/include", LIBS=["opus"], LIBPATH=[lib_utils_external.get_cmake_output_lib_dir(env, "opus")])

    if env["rnnoise"]:
        env.Append(CPPPATH="noise-suppression-for-voice/external/rnnoise/include",
                   LIBS=["RnNoise"],
                   LIBPATH=[lib_utils_external.get_cmake_output_lib_dir(env, "noise-suppression-for-voice/external/rnnoise")],
                   CPPDEFINES=["RNNOISE"])

    if env["lipsync"]:
        lipsync_lib_path = ""
        ovrlipsync_dir = env["ovrlipsync_dir"]

        if env["platform"] == "windows":
            lipsync_lib_path = os.path.join(ovrlipsync_dir, "Lib", "Win64")
        elif env["platform"] == "macos" and env["arch"] == "x86_64":
            lipsync_lib_path = os.path.join(ovrlipsync_dir, "Lib", "MacOS")
        elif env["platform"] == "android":
            if env["arch"] == "arm32":
                lipsync_lib_path = os.path.join(ovrlipsync_dir, "Lib", "Android32")
            elif env["arch"] == "arm64":
                lipsync_lib_path = os.path.join(ovrlipsync_dir, "Lib", "Android64")
            else:
                print("Lipsync is supported only on arm32 and arm64.")
                env.Exit(1)
        else:
            print(f"Lipsync is not supported by the {env["platform"]}:{env["arch"]} platform.")
            env.Exit(1)

        dbg_suffix = "d" if env["dev_build"] else ""
        env.Append(CPPPATH=os.path.join(ovrlipsync_dir, "Include"),
                    LIBS=["OVRLipSyncShim" + dbg_suffix],
                    LIBPATH=[lipsync_lib_path],
                    CPPDEFINES=["OVR_LIP_SYNC"])

    if env.get("is_msvc", False):
        env.Append(LINKFLAGS=["/WX:NO"])

    if env["platform"] in ["linux"]: # , "android"?
        env.Append(
            LINKFLAGS=[
                "-static-libgcc",
                "-static-libstdc++",
            ]
        )
    if env["platform"] == "android":
        env.Append(
            LIBS=[
                "log",
            ]
        )
    print()

def apply_patches(target, source, env: SConsEnvironment):
    rc = lib_utils_external.apply_git_patches(env, patches_to_apply_rmnoise, "noise-suppression-for-voice")
    if rc:
      return rc
    return lib_utils_external.apply_git_patches(env, patches_to_apply_godot, "godot-cpp")

def build_opus(target, source, env: SConsEnvironment):
    extra_flags = []
    if env["platform"] == "web":
        extra_flags += ["-DOPUS_STACK_PROTECTOR=0"]
    if env["platform"] in ["linux", "web"]:
        extra_flags += ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    if env["platform"] in ["macos", "ios"]:
        extra_flags += ["-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"]

    return lib_utils_external.cmake_build_project(env, "opus", extra_flags)

def build_rnnoise(target, source, env: SConsEnvironment):
    extra_flags = []
    if env["platform"] in ["linux", "web"]:
        extra_flags += ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    if env["platform"] in ["macos", "ios"]:
        extra_flags += ["-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"]

    return lib_utils_external.cmake_build_project(env, "noise-suppression-for-voice/external/rnnoise", extra_flags)

env: SConsEnvironment = SConscript("godot-cpp/SConstruct")
env = env.Clone()

args = ARGUMENTS
additional_src = []
setup_options(env, args)
setup_defines_and_flags(env, additional_src)

output_path = env["addon_output_dir"]
if output_path == default_output_dir:
    if env["lipsync"]:
        output_path = default_output_lipsync_dir

lib_utils.get_library_object(env, project_name, lib_name, output_path, src_folder, additional_src)

# Register console commands
env.Command("apply_patches", [], apply_patches)
env.Command("build_opus", [], build_opus)
env.Command("build_rnnoise", [], build_rnnoise)
