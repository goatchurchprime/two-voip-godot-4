#!/usr/bin/env python

from SCons.Script import SConscript
from SCons.Script.SConscript import SConsEnvironment
from SCons.Script import ARGLIST, ARGUMENTS, BUILD_TARGETS, COMMAND_LINE_TARGETS, DEFAULT_TARGETS, Glob

import SCons, SCons.Script
import sys, os, platform, shutil
import lib_utils, lib_utils_external

# Fixing the encoding of the console
if platform.system() == "Windows":
    os.system("chcp 65001")

EnsureSConsVersion(4, 0)  # type: ignore
EnsurePythonVersion(3, 8)  # type: ignore

# Project config
project_name = "TwoVoIP"
lib_name = "twovoip"
default_output_dir = os.path.join("addons", "twovoip", "libs")
src_folder = "src"

# If necessary, add patches from the code
patches_to_apply_rmnoise = [
    "patches/rmnoise-remove-fileio.patch", # Remove fileio from rmnoise library as we get a Windows link error TODO: Work out how to link against the right MSVCRT library
]

patches_to_apply_godot = [
    "patches/godot_cpp_exclude_unused_classes.patch", # Removes unused godot-cpp classes from the build process
    "patches/unity_build.patch", # Speeds up the build by merging the source files. It can increase the size of assemblies.
]

print(
    f"If you add new source files (e.g. .cpp, .c), do not forget to specify them in '{src_folder}/default_sources.json'."
    + f"\n\tOr add them to 'setup_defines_and_flags' inside 'SConstruct'."
)
print("To apply git patches, use 'scons apply_patches'.")
print("To build the opus library, use 'scons build_opus'.")

# Additional console arguments
def setup_options(env: SConsEnvironment, arguments):
    from SCons.Variables import Variables, BoolVariable, EnumVariable, PathVariable

    opts = Variables([], arguments)

    # It must be here for lib_utils.py
    opts.Add(PathVariable("addon_output_dir", "Path to the output directory", default_output_dir, PathVariable.PathIsDirCreate))
    opts.Add(BoolVariable("rnnoise", "Enable rnnoise support", True))
    opts.Add(BoolVariable("webrtc_apm", "Enable the optional WebRTC Audio Processing Module", False))

    opts.Update(env)
    env.Help(opts.GenerateHelpText(env))


# Additional compilation flags
def setup_defines_and_flags(env: SConsEnvironment, src_out: list):
    # Add more sources to `src_out` if needed

    env.Append(
        CPPPATH=["speexdsp/include", "thirdparty/speexdsp/include/speex"],
        CPPDEFINES=["FLOATING_POINT", "USE_KISS_FFT", ("EXPORT", "")],
    )

    if env.get("lto") != "none":
        if env.get("is_msvc", False):
            env.AppendUnique(CCFLAGS=["/GL"],
                             ARFLAGS=["/LTCG"],
                             LINKFLAGS=["/LTCG"],)
        else:
            env.AppendUnique(CCFLAGS=["-flto"],
                             LINKFLAGS=["-flto"],)
    else:
        if env.get("is_msvc", False):
            env.AppendUnique(LINKFLAGS=["/incremental:no"])

    env.Append(CPPPATH="opus/include", LIBS=["opus"], LIBPATH=[lib_utils_external.get_cmake_output_lib_dir(env, "opus")])

    if env["rnnoise"]:
        env.Append(CPPPATH="rnnoise/include",
                   LIBS=["RnNoise"],
                   LIBPATH=[lib_utils_external.get_cmake_output_lib_dir(env, "thirdparty/rnnoise")],
                   CPPDEFINES=["RNNOISE"])

    if env["webrtc_apm"]:
        if env["platform"] != "linux":
            raise RuntimeError("webrtc_apm is currently supported only for Linux development builds")
        apm_build_dir = lib_utils_external.get_meson_build_dir(env, "webrtc-apm")
        apm_library_dir = os.path.join(apm_build_dir, "webrtc", "modules", "audio_processing")
        apm_library = os.path.join(apm_library_dir, "libwebrtc-audio-processing-2.so.1")
        absl_include_dir = "webrtc-audio-processing/subprojects/abseil-cpp-20240722.0"
        if not os.path.isfile(apm_library) or not os.path.isdir(absl_include_dir):
            raise RuntimeError("webrtc_apm=yes requires: scons build_webrtc_apm platform=linux arch=x86_64")
        env.Append(
            CPPDEFINES=["WEBRTC_APM"],
            CPPPATH=[
                "webrtc-audio-processing/webrtc",
                absl_include_dir,
            ],
            LIBPATH=[apm_library_dir],
            LIBS=["webrtc-audio-processing-2"],
            LINKFLAGS=[r"-Wl,-rpath,\$$ORIGIN"],
        )
        env.AppendUnique(CXXFLAGS=["-std=c++20"])
        src_out.append("webrtc_apm_processor.cpp")

    if env.get("is_msvc", False):
        env.Append(CCFLAGS=["/GF"])  # Eliminate Duplicate Strings
        env.Append(LINKFLAGS=["/WX:NO"])

    if env["platform"] in ["linux"] and not env["webrtc_apm"]: # , "android"?
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
    rc = lib_utils_external.apply_git_patches(env, patches_to_apply_rmnoise, "rnnoise")
    if rc:
      return rc
    return lib_utils_external.apply_git_patches(env, patches_to_apply_godot, "godot-cpp")

def get_android_toolchain() -> str:
    sys.path.insert(0, "godot-cpp/tools")
    import android  # type: ignore

    sys.path.pop(0)
    return os.path.join(android.get_android_ndk_root(env), "build/cmake/android.toolchain.cmake")

def build_opus(target, source, env: SConsEnvironment):
    extra_flags = []
    if env["platform"] in ["windows"]:
        extra_flags += ["-DOPUS_STATIC_RUNTIME=ON"]
    if env["platform"] == "web":
        extra_flags += ["-DOPUS_STACK_PROTECTOR=0"]
    if env["platform"] in ["linux", "web"]:
        extra_flags += ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    if env["platform"] in ["macos", "ios"]:
        extra_flags += ["-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"]
    if env["platform"] in ["android"]:
        extra_flags += [f"-DCMAKE_TOOLCHAIN_FILE={get_android_toolchain()}"]

    return lib_utils_external.cmake_build_project(env, "opus", extra_flags)

def build_rnnoise(target, source, env: SConsEnvironment):
    extra_flags = []
    if env["platform"] in ["linux", "web"]:
        extra_flags += ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    if env["platform"] in ["macos", "ios"]:
        extra_flags += ["-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"]
    if env["platform"] in ["android"]:
        extra_flags += [f"-DCMAKE_TOOLCHAIN_FILE={get_android_toolchain()}"]

    return lib_utils_external.cmake_build_project(env, "thirdparty/rnnoise", extra_flags)

def build_webrtc_apm(target, source, env: SConsEnvironment):
    if env["platform"] != "linux":
        print("WebRTC APM build is currently supported only on Linux")
        return 1
    rc = lib_utils_external.meson_build_project(env, "webrtc-apm", "webrtc-audio-processing", [
        "--wrap-mode=forcefallback",
        "-Ddefault_library=shared",
        "-Dabseil-cpp:default_library=static",
        "-Dcpp_std=c++20",
        "-Dbuildtype=release",
    ])
    wrap_lock = os.path.join("webrtc-audio-processing", "subprojects", ".wraplock")
    if os.path.exists(wrap_lock):
        os.remove(wrap_lock)
    if rc:
        return rc
    build_dir = lib_utils_external.get_meson_build_dir(env, "webrtc-apm")
    source_library = os.path.join(build_dir, "webrtc", "modules", "audio_processing", "libwebrtc-audio-processing-2.so.1")
    os.makedirs(env["addon_output_dir"], exist_ok=True)
    shutil.copy2(source_library, os.path.join(env["addon_output_dir"], os.path.basename(source_library)))
    return 0

webrtc_apm_argument = ARGUMENTS.pop("webrtc_apm", None)
env: SConsEnvironment = SConscript("godot-cpp/SConstruct")
if webrtc_apm_argument is not None:
    ARGUMENTS["webrtc_apm"] = webrtc_apm_argument
env = env.Clone()

args = ARGUMENTS
additional_src = []
setup_options(env, args)
setup_defines_and_flags(env, additional_src)
env.GodotCPPDocData("src/gen/doc_data.gen.cpp", source=Glob("doc_classes/*.xml"))

extra_tags = ""

output_path = env["addon_output_dir"]

library = lib_utils.get_library_object(env, project_name, lib_name, extra_tags, output_path, src_folder, additional_src)
env.Clean(env.File(library), env.Dir("#build"))

# Register console commands
env.Command("apply_patches", [], apply_patches)
env.Command("build_opus", [], build_opus)
env.Command("build_rnnoise", [], build_rnnoise)
env.Command("build_webrtc_apm", [], build_webrtc_apm)
