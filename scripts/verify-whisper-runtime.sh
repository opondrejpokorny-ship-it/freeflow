#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_VERSION="1.9.1"
readonly EXPECTED_COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <whisper-cli> <manifest.json> [arm64|x86_64|universal]" >&2
    exit 2
fi

executable="$1"
manifest="$2"
expected_arch="${3:-$(uname -m)}"

if [[ ! -x "${executable}" ]]; then
    echo "Runtime is missing or not executable: ${executable}" >&2
    exit 1
fi

if [[ ! -f "${manifest}" ]]; then
    echo "Runtime manifest is missing: ${manifest}" >&2
    exit 1
fi

python3 -m json.tool "${manifest}" >/dev/null
python3 - "${manifest}" "${EXPECTED_VERSION}" "${EXPECTED_COMMIT}" <<'PY'
import json
import sys

manifest_path, expected_version, expected_commit = sys.argv[1:]
with open(manifest_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

assert payload.get("schemaVersion") == 1, payload
assert payload.get("name") == "whisper.cpp", payload
assert payload.get("version") == expected_version, payload
assert payload.get("commit") == expected_commit, payload
assert payload.get("sharedLibraries") is False, payload
assert payload.get("metalEnabled") is True, payload
assert payload.get("metalLibraryEmbedded") is True, payload
assert payload.get("nativeOptimizations") is False, payload
PY

case "${expected_arch}" in
    arm64|x86_64)
        lipo -verify_arch "${expected_arch}" "${executable}"
        ;;
    universal)
        lipo -verify_arch arm64 x86_64 "${executable}"
        ;;
    *)
        echo "Unsupported expected architecture: ${expected_arch}" >&2
        exit 2
        ;;
esac

unexpected_dependencies="$(
    otool -L "${executable}" \
        | tail -n +2 \
        | awk '{print $1}' \
        | grep -Ev '^(/System/Library/|/usr/lib/)' \
        || true
)"

if [[ -n "${unexpected_dependencies}" ]]; then
    echo "Runtime contains non-system dynamic dependencies:" >&2
    echo "${unexpected_dependencies}" >&2
    exit 1
fi

host_arch="$(uname -m)"
if [[ "${expected_arch}" == "universal" || "${expected_arch}" == "${host_arch}" ]]; then
    version_output="$("${executable}" --version 2>&1)"
    if [[ "${version_output}" != *"${EXPECTED_VERSION}"* ]]; then
        echo "Unexpected whisper-cli version output: ${version_output}" >&2
        exit 1
    fi
fi

printf 'Verified whisper-cli %s for %s (%s)\n' \
    "${EXPECTED_VERSION}" \
    "${expected_arch}" \
    "$(lipo -archs "${executable}")"
