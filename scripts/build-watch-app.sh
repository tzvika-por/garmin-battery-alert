#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
CONNECT_IQ_PROJECT="${PROJECT_ROOT}/watch-app/GarminBatteryAlert/GarminBatteryAlert"
SDK="${CONNECT_IQ_SDK:-}"
DEVELOPER_KEY="${GARMIN_DEVELOPER_KEY:-}"
DEVICE="vivoactive4"

MONKEYC="${SDK}/bin/monkeyc"
SDK_VERSION_FILE="${SDK}/bin/version.txt"
JUNGLE="${CONNECT_IQ_PROJECT}/monkey.jungle"
BUILD_DIR="${PROJECT_ROOT}/build"
OUTPUT="${BUILD_DIR}/GarminBatteryAlert.prg"
SETTINGS_OUTPUT="${BUILD_DIR}/GarminBatteryAlert-settings.json"
TEMP_DIR=""
TEMP_OUTPUT=""
TEMP_SETTINGS_OUTPUT=""

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -- "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | awk '{print $1}'
    else
        fail "install shasum or sha256sum to calculate output checksums"
    fi
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        if [[ "$TEMP_DIR" == "${BUILD_DIR}/.GarminBatteryAlert-build."* ]]; then
            rm -R -- "$TEMP_DIR" || true
        else
            printf 'ERROR: refusing to clean unexpected temporary path: %s\n' "$TEMP_DIR" >&2
        fi
    fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -n "$SDK" ]] || fail "set CONNECT_IQ_SDK to the installed Connect IQ SDK directory"
[[ -n "$DEVELOPER_KEY" ]] || fail "set GARMIN_DEVELOPER_KEY to your Garmin developer key"
[[ -x "$MONKEYC" ]] || fail "Monkey C compiler is missing or not executable: $MONKEYC"
[[ -f "$SDK_VERSION_FILE" ]] || fail "SDK version file is missing: $SDK_VERSION_FILE"
[[ -f "$JUNGLE" ]] || fail "Monkey Jungle file is missing: $JUNGLE"
[[ -f "$DEVELOPER_KEY" && -r "$DEVELOPER_KEY" ]] || fail "Developer key is missing or unreadable: $DEVELOPER_KEY"

mkdir -p "$BUILD_DIR"
TEMP_DIR="$(mktemp -d "${BUILD_DIR}/.GarminBatteryAlert-build.XXXXXX")"
TEMP_OUTPUT="${TEMP_DIR}/GarminBatteryAlert.prg"
TEMP_SETTINGS_OUTPUT="${TEMP_DIR}/GarminBatteryAlert-settings.json"

JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$MONKEYC" \
    -f "$JUNGLE" \
    -o "$TEMP_OUTPUT" \
    -y "$DEVELOPER_KEY" \
    -d "$DEVICE" \
    -w

[[ -s "$TEMP_OUTPUT" ]] || fail "Temporary build output is missing or empty: $TEMP_OUTPUT"
[[ -s "$TEMP_SETTINGS_OUTPUT" ]] || fail "Temporary settings metadata is missing or empty: $TEMP_SETTINGS_OUTPUT"

# Promote the settings companion first, then atomically replace the PRG as the commit point.
# All files are on the same filesystem. A failed compile never changes either final artifact.
mv -f -- "$TEMP_SETTINGS_OUTPUT" "$SETTINGS_OUTPUT"
TEMP_SETTINGS_OUTPUT=""
mv -f -- "$TEMP_OUTPUT" "$OUTPUT"
TEMP_OUTPUT=""
rm -R -- "$TEMP_DIR"
TEMP_DIR=""

[[ -s "$OUTPUT" ]] || fail "Final build output is missing or empty after replacement: $OUTPUT"
[[ -s "$SETTINGS_OUTPUT" ]] || fail "Final settings metadata is missing or empty after replacement: $SETTINGS_OUTPUT"

SDK_VERSION="$(cat "$SDK_VERSION_FILE")"
FILE_SIZE="$(wc -c < "$OUTPUT" | tr -d '[:space:]')"
SHA256="$(sha256_file "$OUTPUT")"

printf 'SDK version: %s\n' "$SDK_VERSION"
printf 'Target device: %s\n' "$DEVICE"
printf 'Output path: %s\n' "$OUTPUT"
printf 'Settings metadata: %s\n' "$SETTINGS_OUTPUT"
printf 'File size: %s bytes\n' "$FILE_SIZE"
printf 'SHA-256: %s\n' "$SHA256"
