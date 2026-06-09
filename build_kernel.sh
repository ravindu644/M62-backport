#!/bin/bash

# Logging functions
log()   { echo -e "\n[INFO]: $*\n"; }
error() { echo -e "\n[ERROR]: $*\n" >&2; exit 1; }

# Model -> device config map
declare -A MODEL_CONFIGS=(
    [beyond0lte]="beyond0lte.config"   # S10e
    [beyond1lte]="beyond1lte.config"   # S10
    [beyond2lte]="beyond2lte.config"   # S10+
    [beyondx]="beyondx.config"         # S10 5G
    [d1]="d1.config"                   # Note10
    [d1xks]="d1xks.config"             # Note10 5G
    [d2s]="d2s.config"                 # Note10+
    [d2x]="d2x.config"                 # Note10+ 5G
)

# Default to beyondx
MODEL="beyondx"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            [[ -z "$2" ]] && error "--model requires a value"
            MODEL="$2"
            shift 2
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

if [[ -z "${MODEL_CONFIGS[$MODEL]+_}" ]]; then
    error "Unknown model '$MODEL'. Valid models: ${!MODEL_CONFIGS[*]}"
fi

DEVICE_CONFIG="${MODEL_CONFIGS[$MODEL]}"
log "BUILD STARTED for model: ${MODEL} (${DEVICE_CONFIG})"

# Init submodules
git submodule update --init --recursive

# Export core variables
export KERNEL_ROOT="$(pwd)"
export ARCH=arm64

# Prepare build environment
mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build" "${HOME}/toolchains"

# Export toolchain paths
export PATH="${HOME}/toolchains/clang-r510928/bin:${PATH}"
export LD_LIBRARY_PATH="${HOME}/toolchains/clang-r510928/lib:${LD_LIBRARY_PATH}"
export BUILD_CC="${HOME}/toolchains/clang-r510928/bin/clang"

# Build options for the kernel
export BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${KERNEL_ROOT}/out"
    -j"$(nproc)"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    HOSTCC=gcc
    HOSTCXX=g++
    CC="${BUILD_CC}"
    CLANG_TRIPLE=aarch64-linux-gnu-
)

build_kernel(){
    # Make default configuration.
    make "${BUILD_OPTIONS[@]}" exynos9820_defconfig "${DEVICE_CONFIG}" custom.config droidspaces.config

    # Configure the kernel (GUI)
    make "${BUILD_OPTIONS[@]}" menuconfig

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" Image || error "Kernel build failed"

    # Copy the built kernel to the build directory
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_ROOT}/build"

    log "BUILD FINISHED..!"
}
build_kernel
