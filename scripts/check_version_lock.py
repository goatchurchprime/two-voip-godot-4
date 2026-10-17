#!/usr/bin/env python3
"""Fail unless the GDScript and every packaged native library share one version."""

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "src/version.h"
NATIVE_SUFFIXES = {".dll", ".dylib", ".so", ".wasm"}


def fail(message: str) -> None:
	print(f"TwoVoIP version lock failed: {message}", file=sys.stderr)
	raise SystemExit(1)


def main() -> None:
	if len(sys.argv) != 2:
		fail("usage: check_version_lock.py PATH_TO_ADDON")

	addon = Path(sys.argv[1])
	header = HEADER.read_text()
	parts = []
	for name in ("MAJOR", "MINOR", "PATCH"):
		match = re.search(rf"#define TWOVOIP_{name} (\d+)", header)
		if match is None:
			fail(f"TWOVOIP_{name} is missing from {HEADER}")
		parts.append(match.group(1))
	version = ".".join(parts)

	gdscript_path = addon / "two_voip.gd"
	gdscript = gdscript_path.read_text()
	match = re.search(r'^const VERSION := "([^"]+)"$', gdscript, re.MULTILINE)
	if match is None or match.group(1) != version:
		found = match.group(1) if match else "missing"
		fail(f"{gdscript_path} expects {found}, native source declares {version}")

	libraries = sorted(path for path in (addon / "libs").rglob("libtwovoip.*") if path.suffix in NATIVE_SUFFIXES)
	if not libraries:
		fail(f"no native libraries found under {addon / 'libs'}")
	version_bytes = version.encode()
	stale = [str(path) for path in libraries if version_bytes not in path.read_bytes()]
	if stale:
		fail(f"native version {version} is absent from: {', '.join(stale)}")

	print(f"TwoVoIP {version}: GDScript and {len(libraries)} native libraries match")


if __name__ == "__main__":
	main()
