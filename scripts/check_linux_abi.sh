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

	case "$library" in
		*.arm64.so) expected_machine="AArch64" ;;
		*.x86_64.so) expected_machine="Advanced Micro Devices X86-64" ;;
		*) expected_machine="" ;;
	esac
	actual_machine="$(readelf --file-header --wide "$library" \
		| sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')"
	if [[ -n "$expected_machine" && "$actual_machine" != "$expected_machine" ]]; then
		echo "TwoVoIP ABI check: $library is $actual_machine; expected $expected_machine" >&2
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
	if grep -Eq 'Shared library: \[(libstdc\+\+|libgcc_s)\.so' <<<"$dynamic_section"; then
		echo "TwoVoIP ABI check: $library does not statically link its GCC runtimes" >&2
		echo "$dynamic_section" | grep -E 'Shared library: \[(libstdc\+\+|libgcc_s)\.so' >&2
		exit 1
	fi

	echo "TwoVoIP ABI check: $library is $actual_machine and requires GLIBC_$required_glibc (limit GLIBC_$maximum_glibc)"
done
