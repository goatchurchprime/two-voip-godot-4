#!/usr/bin/env python3

from SCons.Environment import Environment
from patches import unity_tools

import SCons
import os, json, re


def get_sources(src: list, src_folder: str):
    res = [src_folder + "/" + file for file in src]
    res = unity_tools.generate_unity_build(res, "twovoip_")
    return res


def get_library_object(env: Environment, project_name: str, lib_name: str, output_path: str, src_folder: str, additional_src: list):
    env.Append(CPPPATH=src_folder)

    src = []
    with open(src_folder + "/default_sources.json") as f:
        src = json.load(f)

    scons_cache_path = os.environ.get("SCONS_CACHE")
    if scons_cache_path is None:
        # store all obj's in a dedicated folder
        env["SHOBJPREFIX"] = "#obj/"

    # some additional tags if needed
    additional_tags = ""

    if env["platform"] == "web" and env.get("threads", True):
        additional_tags = ".threads"

    lib_filename = "lib{}.{}.{}.{}{}".format(lib_name, env["platform"], env["target"], env["arch"], additional_tags)
    lib_full_path = os.path.join(output_path, lib_filename + env["SHLIBSUFFIX"])

    if env["platform"] != "macos":
        env.Default(
            env.SharedLibrary(
                target=env.File(lib_full_path),
                source=additional_src + get_sources(src, src_folder),
                SHLIBSUFFIX=env["SHLIBSUFFIX"],
            )
        )
    else:
        generate_framework_folder(env, project_name, lib_name, lib_filename, output_path)
        env.Default(
            env.SharedLibrary(
                target=env.File(os.path.join(output_path, lib_filename + ".framework", lib_filename)),
                source=additional_src + get_sources(src, src_folder),
                SHLIBSUFFIX="",
            )
        )


def get_library_version():
    with open("src/version.h", "r") as f:
        header_content = f.read()

    major_match = re.search(r"#define .*_MAJOR (\d+)", header_content)
    minor_match = re.search(r"#define .*_MINOR (\d+)", header_content)
    patch_match = re.search(r"#define .*_PATCH (\d+)", header_content)

    major_value = int(major_match.group(1)) if major_match else 0
    minor_value = int(minor_match.group(1)) if minor_match else 0
    patch_value = int(patch_match.group(1)) if patch_match else 0

    return f"{major_value}.{minor_value}.{patch_value}"


def generate_framework_folder(env: Environment, project_name: str, lib_name: str, lib_filename: str, output_path: str):
    min_version = env.get("macos_deployment_target", "10.14")
    lib_version = get_library_version()

    info_plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>{lib_filename}</string>
	<key>CFBundleName</key>
	<string>{project_name}</string>
	<key>CFBundleDisplayName</key>
	<string>{project_name}</string>
	<key>CFBundleIdentifier</key>
	<string>ru.dmitriysalnikov.{lib_name}</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright (c) Dmitriy Salnikov.</string>
	<key>CFBundleVersion</key>
	<string>{lib_version}</string>
	<key>CFBundleShortVersionString</key>
	<string>{lib_version}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CSResourcesFileMapped</key>
	<true/>
	<key>DTPlatformName</key>
	<string>macosx</string>
	<key>LSMinimumSystemVersion</key>
	<string>{min_version}</string>
</dict>
</plist>
    """

    res_folder = os.path.join(output_path, lib_filename + ".framework", "Resources")
    os.makedirs(res_folder, exist_ok=True)

    with open(os.path.join(res_folder, "Info.plist"), "w") as info_plist_file:
        info_plist_file.write(info_plist)
