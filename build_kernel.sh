#!/bin/bash

# Logging functions
log()   { echo -e "[INFO]: $*"; }
error() { echo -e "[ERROR]: $*" >&2; exit 1; }

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
    [d2xks]="d2x.config"               # Note10+ 5G (Korean)
)

# Model -> board ID map (for mkbootimg)
declare -A MODEL_BOARDS=(
    [beyond0lte]="SRPRI28A016KU"
    [beyond1lte]="SRPRI28B016KU"
    [beyond2lte]="SRPRI17C016KU"
    [beyondx]="SRPSC04B014KU"
    [d1]="SRPSD26B009KU"
    [d1xks]="SRPSD23A002KU"
    [d2s]="SRPSC14B009KU"
    [d2x]="SRPSC14C009KU"
    [d2xks]="SRPSD23C002KU"
)

# Default to beyondx
MODEL="beyondx"
SKIP_MENUCONFIG=false
ONEUI_VERSION=7

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            [[ -z "$2" ]] && error "--model requires a value"
            MODEL="$2"
            shift 2
            ;;
        --no-menuconfig)
            SKIP_MENUCONFIG=true
            shift
            ;;
        --oneui)
            [[ -z "$2" ]] && error "--oneui requires a value"
            ONEUI_VERSION="$2"
            shift 2
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

[[ "${ONEUI_VERSION}" != "6" && "${ONEUI_VERSION}" != "7" ]] && \
    error "Invalid --oneui value '${ONEUI_VERSION}'. Valid values: 6, 7"

if [[ -z "${MODEL_CONFIGS[$MODEL]+_}" ]]; then
    error "Unknown model '$MODEL'. Valid models: ${!MODEL_CONFIGS[*]}"
fi

DEVICE_CONFIG="${MODEL_CONFIGS[$MODEL]}"
log "BUILD STARTED for model: ${MODEL} (${DEVICE_CONFIG})"

# Init submodules
git submodule update --init --recursive --remote --no-recommend-shallow

# Customization
KERNEL_NAME="ExtremeKernel-KSUNv3.2.0-Droidspaces"
BUILD_DATE="$(date +"%d-%m-%Y_%H-%M-%S")"

# Export core variables
export KERNEL_ROOT="$(pwd)"
export ARCH=arm64

# Prepare build environment
mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build" "${HOME}/toolchains"

# Export toolchain paths
export PATH="${HOME}/toolchains/clang-r510928/bin:${PATH}"
export LD_LIBRARY_PATH="${HOME}/toolchains/clang-r510928/lib:${LD_LIBRARY_PATH}"
export BUILD_CC="${HOME}/toolchains/clang-r510928/bin/clang"

[[ ! -f "${BUILD_CC}" ]] && error "Toolchain not found at ${HOME}/toolchains/clang-r510928"

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
    local ONEUI6_CONFIG=""
    [[ "${ONEUI_VERSION}" == "6" ]] && ONEUI6_CONFIG="oneui6.config"

    make "${BUILD_OPTIONS[@]}" exynos9820_defconfig "${DEVICE_CONFIG}" custom.config droidspaces.config ${ONEUI6_CONFIG}

    [[ "${SKIP_MENUCONFIG}" == false ]] && make "${BUILD_OPTIONS[@]}" menuconfig

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" Image || error "Kernel build failed"

    log "Kernel build finished"
}

pack_boot_image(){
    local OUTPUT_DIR="${KERNEL_ROOT}/build/out/${MODEL}"
    mkdir -p "${OUTPUT_DIR}"

    local BOARD="${MODEL_BOARDS[$MODEL]}"
    local KERNEL_IMAGE="${OUTPUT_DIR}/Image"
    local RAMDISK="${OUTPUT_DIR}/ramdisk.cpio.gz"
    local BOOT_IMG="${OUTPUT_DIR}/boot.img"

    # boot.img parameters
    local BASE=0x10000000
    local CMDLINE='loop.max_part=7'
    local HASHTYPE=sha1
    local HEADER_VERSION=1
    local KERNEL_OFFSET=0x00008000
    local OS_PATCH_LEVEL=2025-08
    local OS_VERSION=15.0.0
    local PAGESIZE=2048
    local RAMDISK_OFFSET=0xF0000000
    local SECOND_OFFSET=0xF0000000
    local TAGS_OFFSET=0x00000100

    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_IMAGE}"

    log "Building ramdisk..."
    pushd "${KERNEL_ROOT}/build/ramdisk" > /dev/null
    find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > "${RAMDISK}" \
        || error "Ramdisk build failed"
    popd > /dev/null

    log "Creating boot.img..."
    "${KERNEL_ROOT}/toolchain/mkbootimg" \
        --base            "${BASE}"            \
        --board           "${BOARD}"           \
        --cmdline         "${CMDLINE}"         \
        --hashtype        "${HASHTYPE}"        \
        --header_version  "${HEADER_VERSION}"  \
        --kernel          "${KERNEL_IMAGE}"    \
        --kernel_offset   "${KERNEL_OFFSET}"   \
        --os_patch_level  "${OS_PATCH_LEVEL}"  \
        --os_version      "${OS_VERSION}"      \
        --pagesize        "${PAGESIZE}"        \
        --ramdisk         "${RAMDISK}"         \
        --ramdisk_offset  "${RAMDISK_OFFSET}"  \
        --second_offset   "${SECOND_OFFSET}"   \
        --tags_offset     "${TAGS_OFFSET}"     \
        -o "${BOOT_IMG}" || error "boot.img creation failed"

    local ZIP_NAME="${KERNEL_NAME}-OneUI${ONEUI_VERSION}-${MODEL}-${BUILD_DATE}.zip"
    local STAGING_DIR="${OUTPUT_DIR}/zip_staging"

    rm -rf "${STAGING_DIR}"
    cp -r "${KERNEL_ROOT}/twrp_zip" "${STAGING_DIR}"
    cp "${BOOT_IMG}" "${STAGING_DIR}/boot.img"

    log "Creating ${ZIP_NAME}..."
    pushd "${STAGING_DIR}" > /dev/null
    zip -9 -r "${KERNEL_ROOT}/build/${ZIP_NAME}" . \
        || error "ZIP creation failed"
    popd > /dev/null

    rm -rf "${STAGING_DIR}"

    log "Done: build/${ZIP_NAME}"
}

build_kernel
pack_boot_image
