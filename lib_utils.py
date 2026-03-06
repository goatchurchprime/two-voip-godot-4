#!/usr/bin/env python3

from SCons.Script.SConscript import SConsEnvironment
from patches import unity_tools

import SCons
import os, json, re


def get_sources(src: list, src_folder: str = "", lib_name: str = "lib_"):
    if len(src_folder):
        res = [os.path.join(src_folder, file) for file in src]
    else:
        res = src.copy()
    res = unity_tools.generate_unity_build(res, lib_name + "_")
    return res


def get_library_object(
    other_env: SConsEnvironment,
    project_name: str,
    lib_name: str,
    extra_tags: str,
    output_path: str,
    src_folder: str,
    additional_src: list,
) -> str:
    env = other_env.Clone()
    env.Append(CPPPATH=src_folder)

    src = json.loads(read_all_text(src_folder + "/default_sources.json"))

    scons_cache_path = os.environ.get("SCONS_CACHE")
    if scons_cache_path is None:
        # store all obj's in a dedicated folder
        env["SHOBJPREFIX"] = "#obj/"
    else:
        env.CacheDir(scons_cache_path)
        env.Decider("MD5")

    # some additional tags if needed
    additional_tags = ""

    if env["platform"] == "web" and env.get("threads", True):
        additional_tags = ".threads"

    lib_filename = (
        "lib{}.{}.{}.{}{}".format(lib_name, env["platform"], env["target"], env["arch"], additional_tags + extra_tags)
        + env["SHLIBSUFFIX"]
    )

    if env["platform"] == "macos":
        generate_framework_folder(env, project_name, lib_name, lib_filename, output_path)
        lib_filename = os.path.join(output_path, os.path.splitext(lib_filename)[0] + ".framework", lib_filename)
    else:
        lib_filename = os.path.join(output_path, lib_filename)

    library = env.SharedLibrary(target=env.File(lib_filename), source=get_sources(additional_src + src, src_folder, lib_name))
    env.NoCache(library)
    env.Default(library)

    return lib_filename


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


def read_all_text(file_path: str, force_utf8: bool = False) -> str | None:
    try:
        if force_utf8:
            raise UnicodeDecodeError("f", bytearray(), 0, 0, "f")
        with open(file_path, "r") as file:
            text_data = file.read()
    except UnicodeDecodeError:
        try:
            with open(file_path, "r", encoding="utf-8") as file:
                text_data = file.read()
        except UnicodeDecodeError as e:
            print(
                "Couldn't open file due to 'UnicodeDecodeError' exception: "
                + (file_path).resolve().as_posix()
                + "\nException: "
                + str(e)
            )
            return None
    return text_data


def write_all_text(file_path: str, text: str) -> bool:
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as file:
        file.write(text)
        return True
    return False


def generate_framework_folder(env: SConsEnvironment, project_name: str, lib_name: str, lib_filename: str, output_path: str):
    min_version = env.get("macos_deployment_target", "10.15")
    lib_version = get_library_version()
    lib_filename_noext = os.path.splitext(lib_filename)[0]

    # Godot has a list of required properties:
    # platform/macos/export/export_plugin.cpp: EditorExportPlatformMacOS::_copy_and_sign_files
    # "CFBundleExecutable"
    # "CFBundleIdentifier"
    # "CFBundlePackageType"
    # "CFBundleInfoDictionaryVersion"
    # "CFBundleName"
    # "CFBundleSupportedPlatforms"

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
	<string>com.goatchurchprime.{lib_name}</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright (c) Julian Todd.</string>
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
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
</dict>
</plist>
    """

    res_folder = os.path.join(output_path, lib_filename_noext + ".framework", "Resources")
    os.makedirs(res_folder, exist_ok=True)

    with open(os.path.join(res_folder, "Info.plist"), "w") as info_plist_file:
        info_plist_file.write(info_plist)
