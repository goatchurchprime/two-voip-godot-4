#!/usr/bin/env python

from SCons.Script import SConscript
from SCons.Script.SConscript import SConsEnvironment
from SCons.Script import ARGLIST, ARGUMENTS, BUILD_TARGETS, COMMAND_LINE_TARGETS, DEFAULT_TARGETS, Glob

import SCons, SCons.Script
import sys, os, platform, subprocess, shutil
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
print("To build the pinned native dependencies, use 'scons build_dependencies'.")

# Additional console arguments
def setup_options(env: SConsEnvironment, arguments):
    from SCons.Variables import Variables, BoolVariable, EnumVariable, PathVariable

    opts = Variables([], arguments)

    # It must be here for lib_utils.py
    opts.Add(PathVariable("addon_output_dir", "Path to the output directory", default_output_dir, PathVariable.PathIsDirCreate))
    opts.Add(BoolVariable("rnnoise", "Enable rnnoise support", True))
    opts.Add(BoolVariable("webrtc_apm", "Build with WebRTC Audio Processing (required except on Web)", env["platform"] != "web"))
    opts.Add("opus_include_dir", "Opus header directory", os.environ.get("TWOVOIP_OPUS_INCLUDE_DIR", "opus/include"))
    opts.Add("opus_library_dir", "Opus library directory", os.environ.get(
        "TWOVOIP_OPUS_LIBRARY_DIR", lib_utils_external.get_cmake_output_lib_dir(env, "opus")))
    opts.Add("rnnoise_include_dir", "RNNoise header directory", os.environ.get("TWOVOIP_RNNOISE_INCLUDE_DIR", "rnnoise/include"))
    opts.Add("rnnoise_library_dir", "RNNoise library directory", os.environ.get(
        "TWOVOIP_RNNOISE_LIBRARY_DIR", lib_utils_external.get_cmake_output_lib_dir(env, "thirdparty/rnnoise")))
    opts.Add("rnnoise_library", "RNNoise library name", os.environ.get("TWOVOIP_RNNOISE_LIBRARY", "RnNoise"))

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

    env.Append(CPPPATH=[env["opus_include_dir"]], LIBS=["opus"], LIBPATH=[env["opus_library_dir"]])

    if env["rnnoise"]:
        env.Append(CPPPATH=[env["rnnoise_include_dir"]],
                   LIBS=[env["rnnoise_library"]],
                   LIBPATH=[env["rnnoise_library_dir"]],
                   CPPDEFINES=["RNNOISE"])

    if env["platform"] == "web" and env["webrtc_apm"]:
        raise RuntimeError("Web builds use browser microphone conditioning and require webrtc_apm=no")
    if env["platform"] != "web" and not env["webrtc_apm"]:
        raise RuntimeError("Native TwoVoIP builds require webrtc_apm=yes")

    if env["webrtc_apm"]:
        apm_build_dir = lib_utils_external.get_meson_build_dir(env, "webrtc-apm")
        apm_library = os.path.join(apm_build_dir, "twovoip-webrtc-apm.lib" if env["platform"] == "windows" else "libtwovoip-webrtc-apm.a")
        absl_include_dir = "webrtc-audio-processing/subprojects/abseil-cpp-20240722.0"
        dependency_targets = {
            "apply_patches",
            "build_opus",
            "build_rnnoise",
            "build_webrtc_apm",
            "build_dependencies",
        }
        building_dependencies = any(target in dependency_targets for target in COMMAND_LINE_TARGETS)
        if (not os.path.isfile(apm_library) or not os.path.isdir(absl_include_dir)) and not building_dependencies:
            raise RuntimeError(f"webrtc_apm=yes requires: scons build_webrtc_apm platform={env['platform']} arch={env['arch']}")
        if not building_dependencies:
            env.Append(
                CPPDEFINES=["WEBRTC_APM"],
                CPPPATH=["webrtc-audio-processing/webrtc", absl_include_dir],
                LIBS=[env.File(apm_library)],
            )
            env.AppendUnique(CXXFLAGS=["-std=c++20"])

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

def _write_meson_cross_file(path: str, binaries: dict, host: dict, args: list, needs_exe_wrapper: bool = True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    def meson_value(value):
        if isinstance(value, list):
            return "[" + ", ".join(repr(item) for item in value) + "]"
        return repr(value)
    with open(path, "w", encoding="utf-8") as cross_file:
        cross_file.write("[binaries]\n")
        for key, value in binaries.items():
            cross_file.write(f"{key} = {meson_value(value)}\n")
        cross_file.write("\n[host_machine]\n")
        for key, value in host.items():
            cross_file.write(f"{key} = {meson_value(value)}\n")
        cross_file.write("\n[properties]\n")
        cross_file.write(f"needs_exe_wrapper = {'true' if needs_exe_wrapper else 'false'}\n")
        cross_file.write("\n[built-in options]\n")
        cross_file.write(f"c_args = {meson_value(args)}\n")
        cross_file.write(f"cpp_args = {meson_value(args + ['-include', 'cstdint'])}\n")


def _combine_webrtc_archives(env: SConsEnvironment, build_dir: str, output_path: str):
    suffix = ".lib" if env["platform"] == "windows" else ".a"
    archives = []
    for root, _, files in os.walk(build_dir):
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(suffix) and os.path.abspath(path) != os.path.abspath(output_path):
                archives.append(path)
    archives.sort()
    if not archives:
        print(f"No WebRTC static archives found below {build_dir}")
        return 1
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    if os.path.exists(output_path):
        os.remove(output_path)
    command_env = env.get("ENV")
    if env["platform"] == "windows":
        command = [env.subst("$AR"), "/NOLOGO", f"/OUT:{output_path}"] + archives
        return subprocess.run(command, env=command_env).returncode
    if env["platform"] in ["macos", "ios"]:
        command = ["libtool", "-static", "-o", output_path] + archives
        return subprocess.run(command, env=command_env).returncode
    mri = [f"CREATE {output_path}"] + [f"ADDLIB {path}" for path in archives] + ["SAVE", "END", ""]
    return subprocess.run([env.subst("$AR"), "-M"], input="\n".join(mri), text=True, env=command_env).returncode


def _android_webrtc_cross_file(env: SConsEnvironment, build_root: str):
    ndk_root = os.environ.get("ANDROID_NDK_ROOT") or env.get("ENV", {}).get("ANDROID_NDK_ROOT")
    if not ndk_root:
        raise RuntimeError("ANDROID_NDK_ROOT is required to build WebRTC APM for Android")
    prebuilt_root = os.path.join(ndk_root, "toolchains", "llvm", "prebuilt")
    hosts = sorted(entry for entry in os.listdir(prebuilt_root) if os.path.isdir(os.path.join(prebuilt_root, entry)))
    if not hosts:
        raise RuntimeError(f"No Android LLVM toolchain found below {prebuilt_root}")
    tool_dir = os.path.join(prebuilt_root, hosts[0], "bin")
    triples = {
        "arm32": ("armv7a-linux-androideabi", "arm", "armv7"),
        "arm64": ("aarch64-linux-android", "aarch64", "armv8-a"),
        "x86_32": ("i686-linux-android", "x86", "i686"),
        "x86_64": ("x86_64-linux-android", "x86_64", "x86_64"),
    }
    triple, cpu_family, cpu = triples[env["arch"]]
    api = str(env.get("android_api_level", 21))
    cross_path = os.path.join(build_root, "android-cross.ini")
    _write_meson_cross_file(cross_path, {
        "c": os.path.join(tool_dir, f"{triple}{api}-clang"),
        "cpp": os.path.join(tool_dir, f"{triple}{api}-clang++"),
        "ar": os.path.join(tool_dir, "llvm-ar"),
        "strip": os.path.join(tool_dir, "llvm-strip"),
    }, {"system": "android", "cpu_family": cpu_family, "cpu": cpu, "endian": "little"}, [])
    return cross_path


def _apple_webrtc_cross_file(env: SConsEnvironment, build_root: str, platform: str, arch: str):
    command_env = env.get("ENV")
    if platform == "macos":
        sdk = "macosx"
        system = "darwin"
        minimum_flag = "-mmacosx-version-min=" + (env["macos_deployment_target"] if env["macos_deployment_target"] != "default" else "10.15")
    else:
        sdk = "iphonesimulator" if env["ios_simulator"] else "iphoneos"
        system = "darwin"
        minimum_flag = ("-mios-simulator-version-min=" if env["ios_simulator"] else "-miphoneos-version-min=") + env["ios_min_version"]
    sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True, env=command_env).strip()
    clang = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "clang"], text=True, env=command_env).strip()
    clangxx = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "clang++"], text=True, env=command_env).strip()
    ar = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "ar"], text=True, env=command_env).strip()
    strip = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "strip"], text=True, env=command_env).strip()
    cpu_family = "aarch64" if arch == "arm64" else "x86_64"
    cross_path = os.path.join(build_root, f"{platform}-{arch}-cross.ini")
    args = ["-arch", arch, "-isysroot", sdk_path, minimum_flag]
    _write_meson_cross_file(cross_path, {"c": clang, "cpp": clangxx, "ar": ar, "strip": strip},
                            {"system": system, "cpu_family": cpu_family, "cpu": arch, "endian": "little"}, args)
    return cross_path


def build_webrtc_apm(target, source, env: SConsEnvironment):
    if env["platform"] == "web":
        print("Web uses browser-provided microphone conditioning; no native WebRTC APM is built")
        return 0
    base_args = [
        "--wrap-mode=forcefallback",
        "-Ddefault_library=static",
        "-Dabseil-cpp:default_library=static",
        "-Dcpp_std=c++20",
        "-Dbuildtype=release",
    ]
    target_build_dir = lib_utils_external.get_meson_build_dir(env, "webrtc-apm")
    builds = [(f'{env["platform"]}_{env["arch"]}', [])]
    if env["platform"] == "android":
        builds[0][1].extend(["--cross-file", _android_webrtc_cross_file(env, target_build_dir)])
    elif env["platform"] == "macos":
        arches = ["x86_64", "arm64"] if env["arch"] == "universal" else [env["arch"]]
        builds = []
        for arch in arches:
            name = f"macos_{arch}"
            builds.append((name, ["--cross-file", _apple_webrtc_cross_file(env, target_build_dir, "macos", arch)]))
    elif env["platform"] == "ios":
        arches = ["x86_64", "arm64"] if env["ios_simulator"] and env["arch"] == "universal" else ["arm64" if env["arch"] == "universal" else env["arch"]]
        builds = []
        for arch in arches:
            name = f"ios_{'simulator_' if env['ios_simulator'] else ''}{arch}"
            builds.append((name, ["--cross-file", _apple_webrtc_cross_file(env, target_build_dir, "ios", arch)]))
    else:
        builds[0][1].append("-Dcpp_args=-include cstdint")

    combined_archives = []
    for build_name, platform_args in builds:
        rc = lib_utils_external.meson_build_project(
            env, "webrtc-apm", "webrtc-audio-processing", base_args + platform_args,
            build_name, ["static library"])
        if rc:
            return rc
        build_dir = lib_utils_external.get_meson_build_dir(env, "webrtc-apm", build_name)
        archive_name = "twovoip-webrtc-apm.lib" if env["platform"] == "windows" else "libtwovoip-webrtc-apm.a"
        combined_path = os.path.join(build_dir, archive_name)
        rc = _combine_webrtc_archives(env, build_dir, combined_path)
        if rc:
            return rc
        combined_archives.append(combined_path)

    final_name = "twovoip-webrtc-apm.lib" if env["platform"] == "windows" else "libtwovoip-webrtc-apm.a"
    final_path = os.path.join(target_build_dir, final_name)
    if len(combined_archives) == 1:
        if os.path.abspath(combined_archives[0]) != os.path.abspath(final_path):
            os.makedirs(target_build_dir, exist_ok=True)
            shutil.copy2(combined_archives[0], final_path)
    else:
        command = ["lipo", "-create"] + combined_archives + ["-output", final_path]
        rc = subprocess.run(command, env=env.get("ENV")).returncode
        if rc:
            return rc
    wrap_lock = os.path.join("webrtc-audio-processing", "subprojects", ".wraplock")
    if os.path.exists(wrap_lock):
        os.remove(wrap_lock)
    return 0

def set_portable_linux_rpath(target, source, env: SConsEnvironment):
    patchelf = os.environ.get("TWOVOIP_PATCHELF")
    if not patchelf:
        return 0
    return subprocess.run([patchelf, "--set-rpath", "$ORIGIN", str(target[0])]).returncode

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
if env["platform"] == "linux" and os.environ.get("TWOVOIP_PATCHELF"):
    env.AddPostAction(library, set_portable_linux_rpath)
env.Clean(env.File(library), env.Dir("#build"))

# Register console commands
env.Command("apply_patches", [], apply_patches)
env.Command("build_opus", [], build_opus)
env.Command("build_rnnoise", [], build_rnnoise)
env.Command("build_webrtc_apm", [], build_webrtc_apm)
env.Alias("build_dependencies", ["build_opus", "build_rnnoise", "build_webrtc_apm"])
