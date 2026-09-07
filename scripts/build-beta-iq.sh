#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
CONNECT_IQ_PROJECT="${PROJECT_ROOT}/watch-app/GarminBatteryAlert/GarminBatteryAlert"
SDK="${CONNECT_IQ_SDK:-}"
DEVELOPER_KEY="${GARMIN_DEVELOPER_KEY:-}"
MONKEYC="${SDK}/bin/monkeyc"
PRODUCTION_MANIFEST="${CONNECT_IQ_PROJECT}/manifest.xml"
OUTPUT_DIR="${PROJECT_ROOT}/build/beta"
OUTPUT="${OUTPUT_DIR}/GarminBatteryAlert-beta.iq"
STAGING_ROOT=""
STAGING_PROJECT=""
OUTPUT_TEMP_DIR=""
TEMP_OUTPUT=""

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
    if [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
        if [[ "$STAGING_ROOT" == "${STAGING_PREFIX}"* ]]; then
            rm -R -- "$STAGING_ROOT" || true
        else
            printf 'ERROR: refusing to clean unexpected staging path: %s\n' "$STAGING_ROOT" >&2
        fi
    fi

    if [[ -n "$OUTPUT_TEMP_DIR" && -d "$OUTPUT_TEMP_DIR" ]]; then
        if [[ "$OUTPUT_TEMP_DIR" == "${OUTPUT_DIR}/.GarminBatteryAlert-beta."* ]]; then
            rm -R -- "$OUTPUT_TEMP_DIR" || true
        else
            printf 'ERROR: refusing to clean unexpected output path: %s\n' "$OUTPUT_TEMP_DIR" >&2
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
[[ -f "$DEVELOPER_KEY" && -r "$DEVELOPER_KEY" ]] || fail "developer key is missing or unreadable: $DEVELOPER_KEY"
[[ -f "$PRODUCTION_MANIFEST" ]] || fail "production manifest is missing: $PRODUCTION_MANIFEST"
[[ -f "${CONNECT_IQ_PROJECT}/monkey.jungle" ]] || fail "Monkey Jungle file is missing"
[[ -d "${CONNECT_IQ_PROJECT}/source" ]] || fail "source directory is missing"
[[ -d "${CONNECT_IQ_PROJECT}/resources" ]] || fail "resources directory is missing"

BETA_APP_ID="${GARMIN_BETA_APP_ID:-}"
[[ -n "$BETA_APP_ID" ]] || fail "set GARMIN_BETA_APP_ID to your lowercase Beta application UUID"
[[ "$BETA_APP_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || fail "Beta application ID is not a lowercase UUID"

PRODUCTION_APP_ID="$(sed -nE 's/.*<iq:application id="([^"]+)".*/\1/p' "$PRODUCTION_MANIFEST")"
[[ "$PRODUCTION_APP_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] || fail "production application ID is missing or invalid"
[[ "$BETA_APP_ID" != "$PRODUCTION_APP_ID" ]] || fail "Beta and production application IDs must differ"
[[ "$(sed -nE 's/.*minApiLevel="([^"]+)".*/\1/p' "$PRODUCTION_MANIFEST")" == "3.2.0" ]] || fail "minimum API must remain 3.2.0"
[[ "$(sed -nE 's/.*<iq:product id="([^"]+)".*/\1/p' "$PRODUCTION_MANIFEST")" == "vivoactive4" ]] || fail "the only target must remain vivoactive4"
[[ "$(grep -c '<iq:product id=' "$PRODUCTION_MANIFEST")" == "1" ]] || fail "manifest must contain exactly one product"
grep -q '<iq:uses-permission id="Background"/>' "$PRODUCTION_MANIFEST" || fail "Background permission is missing"
grep -q '<iq:uses-permission id="Communications"/>' "$PRODUCTION_MANIFEST" || fail "Communications permission is missing"
grep -q '<property id="RelayApiKey" type="string"></property>' "${CONNECT_IQ_PROJECT}/resources/settings/properties.xml" || fail "RelayApiKey default must remain empty"
grep -q 'propertyKey="@Properties.RelayApiKey"' "${CONNECT_IQ_PROJECT}/resources/settings/settings.xml" || fail "RelayApiKey setting is missing"
grep -q 'propertyKey="@Properties.RelayBaseUrl"' "${CONNECT_IQ_PROJECT}/resources/settings/settings.xml" || fail "RelayBaseUrl setting is missing"

MANIFEST_BEFORE="$(sha256_file "$PRODUCTION_MANIFEST")"

mkdir -p "$OUTPUT_DIR"
TEMP_BASE="${TMPDIR:-/tmp}"
STAGING_PREFIX="${TEMP_BASE%/}/GarminBatteryAlert-beta-stage."
STAGING_ROOT="$(mktemp -d "${STAGING_PREFIX}XXXXXX")"
STAGING_PROJECT="${STAGING_ROOT}/GarminBatteryAlert"
mkdir -p "$STAGING_PROJECT"
cp -p "${CONNECT_IQ_PROJECT}/manifest.xml" "${CONNECT_IQ_PROJECT}/monkey.jungle" "$STAGING_PROJECT/"
cp -R "${CONNECT_IQ_PROJECT}/source" "${CONNECT_IQ_PROJECT}/resources" "$STAGING_PROJECT/"

STAGED_MANIFEST_TEMP="${STAGING_PROJECT}/.manifest.xml.tmp"
sed "s/id=\"${PRODUCTION_APP_ID}\"/id=\"${BETA_APP_ID}\"/" "${STAGING_PROJECT}/manifest.xml" > "$STAGED_MANIFEST_TEMP"
mv -f -- "$STAGED_MANIFEST_TEMP" "${STAGING_PROJECT}/manifest.xml"

[[ "$(sed -nE 's/.*<iq:application id="([^"]+)".*/\1/p' "${STAGING_PROJECT}/manifest.xml")" == "$BETA_APP_ID" ]] || fail "staged manifest does not contain the Beta application ID"
cmp -s "${CONNECT_IQ_PROJECT}/monkey.jungle" "${STAGING_PROJECT}/monkey.jungle" || fail "staged Monkey Jungle file diverged"
diff -qr "${CONNECT_IQ_PROJECT}/source" "${STAGING_PROJECT}/source" >/dev/null || fail "staged source diverged"
diff -qr "${CONNECT_IQ_PROJECT}/resources" "${STAGING_PROJECT}/resources" >/dev/null || fail "staged resources diverged"

RESTORED_MANIFEST="${STAGING_PROJECT}/.manifest.production.xml"
sed "s/id=\"${BETA_APP_ID}\"/id=\"${PRODUCTION_APP_ID}\"/" "${STAGING_PROJECT}/manifest.xml" > "$RESTORED_MANIFEST"
cmp -s "$PRODUCTION_MANIFEST" "$RESTORED_MANIFEST" || fail "staged manifest diverged by more than the Beta application ID"
rm -f -- "$RESTORED_MANIFEST"

OUTPUT_TEMP_DIR="$(mktemp -d "${OUTPUT_DIR}/.GarminBatteryAlert-beta.XXXXXX")"
TEMP_OUTPUT="${OUTPUT_TEMP_DIR}/GarminBatteryAlert-beta.iq"

JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$MONKEYC" \
    -e \
    -f "${STAGING_PROJECT}/monkey.jungle" \
    -o "$TEMP_OUTPUT" \
    -y "$DEVELOPER_KEY" \
    -w

[[ -s "$TEMP_OUTPUT" ]] || fail "temporary Beta package is missing or empty: $TEMP_OUTPUT"
[[ "$(sha256_file "$PRODUCTION_MANIFEST")" == "$MANIFEST_BEFORE" ]] || fail "production manifest changed during Beta packaging"

mv -f -- "$TEMP_OUTPUT" "$OUTPUT"
TEMP_OUTPUT=""
rm -R -- "$OUTPUT_TEMP_DIR"
OUTPUT_TEMP_DIR=""
rm -R -- "$STAGING_ROOT"
STAGING_ROOT=""

[[ -s "$OUTPUT" ]] || fail "final Beta package is missing or empty: $OUTPUT"

FILE_SIZE="$(wc -c < "$OUTPUT" | tr -d '[:space:]')"
SHA256="$(sha256_file "$OUTPUT")"

printf 'Production application ID: %s\n' "$PRODUCTION_APP_ID"
printf 'Beta application ID: %s\n' "$BETA_APP_ID"
printf 'Target device: vivoactive4\n'
printf 'Minimum API: 3.2.0\n'
printf 'Output path: %s\n' "$OUTPUT"
printf 'File size: %s bytes\n' "$FILE_SIZE"
printf 'SHA-256: %s\n' "$SHA256"
