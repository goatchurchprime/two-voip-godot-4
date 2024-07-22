#!/usr/bin/env python

from SCons.Script import SConscript
from SCons.Environment import Environment

import SCons, SCons.Script
import os, platform
import lib_utils, lib_utils_external

# Fixing the encoding of the console
if platform.system() == "Windows":
    os.system("chcp 65001")

# Project config
project_name = "TwoVoIP"
lib_name = "twovoip"
output_dir = os.path.join("addons", "twovoip", "libs")
src_folder = "src"

# If necessary, add patches from the code
patches_to_apply = [
    "patches/godot_cpp_exclude_unused_classes.patch", # Removes unused godot-cpp classes from the build process
    "patches/unity_build.patch", # Speeds up the build by merging the source files. It can increase the size of assemblies.
    "patches/web_threads.patch", # Adds the build flag that appeared in Godot 4.3. Required for a web build compatible with Godot 4.3.
    ]

print("If you add new source files (e.g. .cpp, .c), do not forget to specify them in 'src/default_sources.json'.\n\tOr add them to 'setup_defines_and_flags' inside 'lib_utils.py '.")
print("To apply git patches, use 'scons apply_patches'.")
print("To build the opus library, use 'scons build_opus'.")

# Additional console arguments
def setup_options(env: Environment, arguments):
    from SCons.Variables import Variables, BoolVariable, EnumVariable, PathVariable
    opts = Variables([], arguments)

    # It must be here for lib_utils.py
    opts.Add(PathVariable("addon_output_dir", "Path to the output directory", output_dir, PathVariable.PathIsDirCreate))

    opts.Add(BoolVariable("lipsync", "Enable lipsync support", False))
    opts.Add(BoolVariable("lto", "Link-time optimization", False))

    opts.Update(env)
    Help(opts.GenerateHelpText(env))


# Additional compilation flags
def setup_defines_and_flags(env: Environment, src_out):
    # Add more sources to `src_out` if needed

    if env["lto"]:
        if env.get("is_msvc", False):
            env.AppendUnique(CCFLAGS=["/GL"])
            env.AppendUnique(ARFLAGS=["/LTCG"])
            env.AppendUnique(LINKFLAGS=["/LTCG"])
        else:
            env.AppendUnique(CCFLAGS=["-flto"])
            env.AppendUnique(LINKFLAGS=["-flto"])

    env.Append(CPPPATH="opus/include", LIBS=["opus"], LIBPATH=[lib_utils_external.get_cmake_output_lib_dir(env, "opus")])
    if env["lipsync"]:
        lipsync_lib_path = ""
        if env["platform"] == "windows":
            lipsync_lib_path = "OVRLipSyncNative/Lib/Win64"
        elif env["platform"] == "macos":
            lipsync_lib_path = "OVRLipSyncNative/Lib/MacOS"
        elif env["platform"] == "android":
            if env["arch"] == "arm32":
                lipsync_lib_path = "OVRLipSyncNative/Lib/Android32"
            elif env["arch"] == "arm64":
                lipsync_lib_path = "OVRLipSyncNative/Lib/Android64"
            else:
                print("Lipsync is supported only on arm32 and arm64.")
                env.Exit(1)
        else:
            print(f"Lipsync is not supported by the {env["platform"]} platform.")
            env.Exit(1)

        env.Append(CPPPATH="OVRLipSyncNative/Include",
                    LIBS=["OVRLipSyncShim"],
                    LIBPATH=[lipsync_lib_path],
                    CPPDEFINES=["OVR_LIP_SYNC"])

    if env["platform"] == "windows":
        env.Append(LINKFLAGS=["/WX:NO"])

    if env["platform"] in ["linux", "android"]:
        env.Append(
            LINKFLAGS=[
                "-static-libgcc",
                "-static-libstdc++",
            ]
        )
    print()


def apply_patches(target, source, env: Environment):
    return lib_utils_external.apply_git_patches(env, patches_to_apply)


def build_opus(target, source, env: Environment):
    extra_flags = []
    if env["platform"] == "web":
        extra_flags += ["-DOPUS_STACK_PROTECTOR=0"]
    if env["platform"] in ["linux", "web"]:
        extra_flags += ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]

    return lib_utils_external.cmake_build_project(env, "opus", extra_flags)

env: Environment = SConscript("godot-cpp/SConstruct")
env = env.Clone()

args = ARGUMENTS
additional_src = []
setup_options(env, args)
setup_defines_and_flags(env, additional_src)

lib_utils.get_library_object(env, project_name, lib_name, env["addon_output_dir"], src_folder, additional_src)

# Register console commands
env.Command("apply_patches", [], apply_patches)
env.Command("build_opus", [], build_opus)
