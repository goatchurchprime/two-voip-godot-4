#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# For reference:
# - CCFLAGS are compilation flags shared between C and C++
# - CFLAGS are for C-specific compilation flags
# - CXXFLAGS are for C++-specific compilation flags
# - CPPFLAGS are for pre-processor flags
# - CPPDEFINES are for pre-processor defines
# - LINKFLAGS are for linking flags

sources = []


# Opus (REQUIRES PRECOMPILE)

if env["platform"] == "windows":
    env.Append(CPPPATH=["opus/include"], LIBS=["opus/build/Release/opus.lib"])
    env.Append(LINKFLAGS = ['/WX:NO'])
else:
    env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="opus/build")

if env["platform"] == "linux":
    env.Append(CXXFLAGS = ['-fpermissive'])


# Speex (resampler / jitter buffer)

#env.Append(CPPPATH=["thirdparty/speex/include"])
env.Append(CPPDEFINES={"FLOATING_POINT": None, "USE_SMALLFT": None}) # "EXPORT": None ?
if env['arch'] == "amd64" or env['arch'] == "x86_64":
    env.Append(CPPDEFINES={"USE_SSE": None, "USE_SSE2": None})
elif env['arch'] == "arm64":
    env.Append(CPPDEFINES={"USE_NEON": None})
sources += ["src/speex_resampler/resample.c"]

# etc


# OneVOIP Extension

if env["platform"] == "windows":
    env['CCPDBFLAGS'] = '/Zi /Fd${TARGET}.pdb'

# env.Append(CPPDEFINES={"NDEBUG": None}) # For release builds
sources += Glob("src/*.cpp")

if env["platform"] == "macos":
    library = env.SharedLibrary(
        "demo_rtc/bin/libonevoip.{}.{}.framework/libonevoip.{}.{}.{}{}".format(
            env["platform"], env["target"], env["platform"], env["target"], env["arch"], env["SHLIBSUFFIX"]
        ),
        source=sources,
    )
else:
    library = env.SharedLibrary(
        "addons/twovoip/libtwovoip{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
        source=sources,
    )

Default(library)
