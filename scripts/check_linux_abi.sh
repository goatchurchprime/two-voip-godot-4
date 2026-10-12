#!/usr/bin/env bash

set -euo pipefail

maximum_glibc="${TWOVOIP_MAX_GLIBC:-2.35}"

if [[ "$#" -eq 0 ]]; then
	echo "usage: $0 LIBRARY.so [LIBRARY.so ...]" >&2
	exit 2
fi

for library in "$@"; do
	if [[ ! -f "$library" ]]; then
		echo "TwoVoIP ABI check: library not found: $library" >&2
		exit 1
	fi

	required_glibc="$({
		readelf --version-info --wide "$library" \
			| sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p'
	} | sort -Vu | tail -n 1)"

	if [[ -z "$required_glibc" ]]; then
		echo "TwoVoIP ABI check: no GLIBC version requirements found in $library" >&2
		exit 1
	fi

	newest_version="$(printf '%s\n%s\n' "$maximum_glibc" "$required_glibc" \
		| sort -V | tail -n 1)"
	if [[ "$newest_version" != "$maximum_glibc" ]]; then
		echo "TwoVoIP ABI check: $library requires GLIBC_$required_glibc; maximum supported is GLIBC_$maximum_glibc" >&2
		exit 1
	fi

	dynamic_section="$(readelf --dynamic --wide "$library")"
	if grep -q '/nix/store/' <<<"$dynamic_section"; then
		echo "TwoVoIP ABI check: $library contains a Nix store runtime path" >&2
		echo "$dynamic_section" | grep '/nix/store/' >&2
		exit 1
	fi

	echo "TwoVoIP ABI check: $library requires GLIBC_$required_glibc (limit GLIBC_$maximum_glibc)"
done
