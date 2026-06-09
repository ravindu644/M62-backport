#!/bin/bash

echo -e "\n[INFO]: BUILD STARTED..!\n"

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
    make "${BUILD_OPTIONS[@]}" exynos9820_defconfig beyondx.config

    # Configure the kernel (GUI)
    make "${BUILD_OPTIONS[@]}" menuconfig

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" Image || exit 1

    # Copy the built kernel to the build directory
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_ROOT}/build"

    echo -e "\n[INFO]: BUILD FINISHED..!"
}
build_kernel
