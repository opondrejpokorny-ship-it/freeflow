#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WHISPER_CPP_REPOSITORY="https://github.com/ggml-org/whisper.cpp.git"
readonly WHISPER_CPP_VERSION="1.9.1"
readonly WHISPER_CPP_COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"
readonly MINIMUM_MACOS_VERSION="13.0"

ARCH="${ARCH:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build/whisper-runtime/${ARCH}}"
SOURCE_DIR="${WHISPER_CPP_SOURCE_DIR:-${ROOT_DIR}/build/vendor/whisper.cpp-${WHISPER_CPP_COMMIT}}"
BUILD_ROOT="${WHISPER_CPP_BUILD_ROOT:-${ROOT_DIR}/build/vendor/whisper.cpp-build-${WHISPER_CPP_COMMIT}}"

case "${ARCH}" in
    arm64|x86_64|universal) ;;
    *)
        echo "Unsupported ARCH=${ARCH}. Expected arm64, x86_64, or universal." >&2
        exit 2
        ;;
esac

for command in git cmake xcrun otool lipo; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "Missing required build tool: ${command}" >&2
        exit 2
    fi
done

prepare_source() {
    local actual_commit=""

    if [[ -d "${SOURCE_DIR}/.git" ]]; then
        actual_commit="$(git -C "${SOURCE_DIR}" rev-parse HEAD 2>/dev/null || true)"
    fi

    if [[ -e "${SOURCE_DIR}" && "${actual_commit}" != "${WHISPER_CPP_COMMIT}" ]]; then
        echo "Discarding stale whisper.cpp source cache at ${SOURCE_DIR}" >&2
        rm -rf "${SOURCE_DIR}"
    fi

    if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
        mkdir -p "$(dirname "${SOURCE_DIR}")"
        git init --quiet "${SOURCE_DIR}"
        git -C "${SOURCE_DIR}" remote add origin "${WHISPER_CPP_REPOSITORY}"
        git -C "${SOURCE_DIR}" -c protocol.version=2 fetch \
            --quiet --depth 1 --no-tags origin "${WHISPER_CPP_COMMIT}"
        git -C "${SOURCE_DIR}" checkout --quiet --detach FETCH_HEAD
    fi

    actual_commit="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
    if [[ "${actual_commit}" != "${WHISPER_CPP_COMMIT}" ]]; then
        echo "whisper.cpp source verification failed: expected ${WHISPER_CPP_COMMIT}, got ${actual_commit}" >&2
        exit 1
    fi
}

logical_cpu_count() {
    sysctl -n hw.logicalcpu 2>/dev/null || echo 4
}

build_architecture() {
    local target_arch="$1"
    local build_dir="${BUILD_ROOT}/${target_arch}"
    local executable="${build_dir}/bin/whisper-cli"

    cmake -S "${SOURCE_DIR}" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${target_arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MINIMUM_MACOS_VERSION}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_TESTS=OFF \
        -DWHISPER_BUILD_SERVER=OFF \
        -DWHISPER_BUILD_EXAMPLES=ON \
        -DWHISPER_CURL=OFF \
        -DWHISPER_SDL2=OFF \
        -DGGML_NATIVE=OFF \
        -DGGML_OPENMP=OFF \
        -DGGML_METAL=ON \
        -DGGML_METAL_EMBED_LIBRARY=ON

    cmake --build "${build_dir}" \
        --config Release \
        --target whisper-cli \
        --parallel "$(logical_cpu_count)"

    if [[ ! -x "${executable}" ]]; then
        echo "whisper-cli was not produced at ${executable}" >&2
        exit 1
    fi

    printf '%s\n' "${executable}"
}

verify_system_dependencies_only() {
    local executable="$1"
    local unexpected_dependencies

    unexpected_dependencies="$(
        otool -L "${executable}" \
            | tail -n +2 \
            | awk '{print $1}' \
            | grep -Ev '^(/System/Library/|/usr/lib/)' \
            || true
    )"

    if [[ -n "${unexpected_dependencies}" ]]; then
        echo "whisper-cli contains non-system dynamic dependencies:" >&2
        echo "${unexpected_dependencies}" >&2
        exit 1
    fi
}

prepare_source
mkdir -p "${OUTPUT_DIR}"

case "${ARCH}" in
    arm64|x86_64)
        built_executable="$(build_architecture "${ARCH}")"
        cp "${built_executable}" "${OUTPUT_DIR}/whisper-cli"
        architectures_json="[\"${ARCH}\"]"
        ;;
    universal)
        arm64_executable="$(build_architecture arm64)"
        x86_64_executable="$(build_architecture x86_64)"
        lipo -create \
            "${arm64_executable}" \
            "${x86_64_executable}" \
            -output "${OUTPUT_DIR}/whisper-cli"
        architectures_json='["arm64", "x86_64"]'
        ;;
esac

chmod 0755 "${OUTPUT_DIR}/whisper-cli"
verify_system_dependencies_only "${OUTPUT_DIR}/whisper-cli"

cat > "${OUTPUT_DIR}/whisper-runtime.json" <<EOF
{
  "schemaVersion": 1,
  "name": "whisper.cpp",
  "version": "${WHISPER_CPP_VERSION}",
  "commit": "${WHISPER_CPP_COMMIT}",
  "sourceRepository": "${WHISPER_CPP_REPOSITORY}",
  "architectures": ${architectures_json},
  "minimumMacOSVersion": "${MINIMUM_MACOS_VERSION}",
  "sharedLibraries": false,
  "metalEnabled": true,
  "metalLibraryEmbedded": true,
  "nativeOptimizations": false
}
EOF

host_arch="$(uname -m)"
if [[ "${ARCH}" == "universal" || "${ARCH}" == "${host_arch}" ]]; then
    "${OUTPUT_DIR}/whisper-cli" --version >/dev/null
fi

printf 'Built whisper.cpp %s (%s) for %s at %s\n' \
    "${WHISPER_CPP_VERSION}" \
    "${WHISPER_CPP_COMMIT}" \
    "$(lipo -archs "${OUTPUT_DIR}/whisper-cli")" \
    "${OUTPUT_DIR}/whisper-cli"
