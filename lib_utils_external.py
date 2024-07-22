#!/usr/bin/env python3

from SCons.Environment import Environment
from SCons.Util import WhereIs

import SCons
import os, subprocess


# Get the name of the cmake build directory
def get_cmake_build_dir_name(env: Environment) -> str:
    if env.get("threads", True) and env["platform"] == "web":
        return f"{env["platform"]}_{env["arch"]}_threads"
    return f"{env["platform"]}_{env["arch"]}"


# Get the name of the output folder of the cmake library
def get_cmake_output_lib_dir(env: Environment, lib_path: str) -> str:
    return os.path.join(lib_path, get_cmake_build_dir_name(env), "Debug" if env["dev_build"] else "Release")


def print_subprocess_result(result, prefix: str):
    if result.stdout:
        print(f"{prefix} output: {result.stdout}")
    if result.stderr:
        print(f"{prefix} errors: {result.stderr}")


def apply_git_patches(env: Environment, patches_to_apply: list):
    for patch in patches_to_apply:
        print()
        try:
            result = subprocess.run(
                [
                    "git",
                    "apply",
                    "--directory=godot-cpp",
                    "--ignore-space-change",
                    "--ignore-whitespace",
                    "--reverse",
                    "--check",
                    patch,
                ],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding="utf-8",
            )
            print(f"Already applied patch: '{patch}'")
            continue
        except subprocess.CalledProcessError as e:
            print(f"Trying to apply a patch: '{patch}'")

        try:
            result = subprocess.run(
                ["git", "apply", "--directory=godot-cpp", "--ignore-space-change", "--ignore-whitespace", patch],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding="utf-8",
            )
            print_subprocess_result(result, "git")
            print(f"Successfully applied patch: {patch}")
        except subprocess.CalledProcessError as e:
            print_subprocess_result(e, "git")
            print("Please fix the patches, disable them, or try to git reset!")
            return 1
    print()
    return 0


def cmake_build_project(env: Environment, lib_path: str, extra_args: list, extra_c_compiler_flags: dict = {}):
    print()
    arch = env["arch"]
    platform = env["platform"]
    platform_args = []
    build_args = []
    compiler_flags = extra_c_compiler_flags.get("c_flags", []).copy()
    linker_flags = extra_c_compiler_flags.get("linker_flags", []).copy()

    if platform == "windows":
        platform_args += ["-G", "Visual Studio 17 2022",
                          "-A", "Win32" if arch == "x86_32" else "x64" if arch == "x86_64" else "ARM",]
    elif platform == "linux":
        platform_args += ["-G", "Ninja Multi-Config",]
    elif platform == "macos":
        platform_args += ["-G", "Ninja Multi-Config",
                        "-DCMAKE_SYSTEM_NAME=Darwin",
                        "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.14",]
    elif platform == "ios":
        platform_args += ["-G", "Ninja Multi-Config",
                        "-DCMAKE_SYSTEM_NAME=iOS",
                        "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.14",]
    elif platform == "android":
        arch_map = {
            "arm32": "armeabi-v7a",
            "arm64": "arm64-v8a",
            "x86_32":  "x86",
            "x86_64":"x86_64",
        }
        platform_args += ["-G", "Ninja Multi-Config",
                        f"-DCMAKE_TOOLCHAIN_FILE={os.getenv("ANDROID_HOME")}/ndk/25.2.9519653/build/cmake/android.toolchain.cmake",
                        f"-DANDROID_ABI={arch_map[arch]}", f"-DANDROID_PLATFORM={env.get("android_api_level", 21)}",]
    elif platform == "web":
        platform_args += ["-G", "Ninja Multi-Config",
                        f"-DCMAKE_TOOLCHAIN_FILE={os.path.dirname(WhereIs("emcc"))}/cmake/Modules/Platform/Emscripten.cmake",]
        if env.get("threads", True):
            compiler_flags += ["-sUSE_PTHREADS=1"]
            linker_flags += ["-sUSE_PTHREADS=1"]

    build_args += ["--config", "Debug" if env["dev_build"] else "Release"]

    if len(compiler_flags):
        platform_args += [f"-DCMAKE_C_FLAGS={";".join(compiler_flags)}", f"-DCMAKE_CXX_FLAGS={";".join(compiler_flags)}"]
    if len(linker_flags):
        platform_args += [f"-DCMAKE_EXE_LINKER_FLAGS={";".join(linker_flags)}"]

    curdir = os.curdir
    os.chdir(lib_path)
    try:
        result = subprocess.run(
            ["cmake", f"-B{get_cmake_build_dir_name(env)}"] + platform_args + extra_args,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
        )
        print_subprocess_result(result, "cmake config")

        result = subprocess.run(
            ["cmake", "--build", get_cmake_build_dir_name(env)] + build_args,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
        )
        print_subprocess_result(result, "cmake build")

        print(f"Successfully build: {lib_path}")
    except subprocess.CalledProcessError as e:
        print_subprocess_result(e, "cmake")
        print(f"cmake can't build {lib_path}. Please fix the errors!")
        return 1
    finally:
        os.chdir(curdir)

    print()
    return 0
