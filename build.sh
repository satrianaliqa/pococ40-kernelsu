#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${ROOT_DIR}/work"
KERNEL_DIR="${WORK_DIR}/kernel"
OUT_DIR="${WORK_DIR}/out"
TOOLCHAIN_DIR="${ROOT_DIR}/toolchain/clang-r416183b"

KERNEL_REPO="https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git"
KERNEL_BRANCH="frost-r-oss"
KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
KSU_COMMIT="e3292239"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b.tar.gz"

JOBS="${JOBS:-$(nproc)}"

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${TOOLCHAIN_DIR}"

if [ ! -d "${TOOLCHAIN_DIR}/bin" ]; then
    echo "[1/5] Downloading AOSP clang-r416183b..."
    curl -fL "${CLANG_URL}" -o "${WORK_DIR}/clang-r416183b.tar.gz"
    tar -xzf "${WORK_DIR}/clang-r416183b.tar.gz" -C "${TOOLCHAIN_DIR}"
    rm -f "${WORK_DIR}/clang-r416183b.tar.gz"
else
    echo "[1/5] Using existing toolchain at ${TOOLCHAIN_DIR}"
fi

if [ ! -d "${KERNEL_DIR}/.git" ]; then
    echo "[2/5] Cloning Xiaomi frost-r-oss kernel source..."
    git clone --depth=1 -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_DIR}"
else
    echo "[2/5] Using existing kernel source at ${KERNEL_DIR}"
fi

if [ ! -d "${KERNEL_DIR}/KernelSU-Next/.git" ]; then
    echo "[3/5] Cloning KernelSU-Next @ ${KSU_COMMIT}..."
    git clone "${KSU_REPO}" "${KERNEL_DIR}/KernelSU-Next"
fi
git -C "${KERNEL_DIR}/KernelSU-Next" checkout -f "${KSU_COMMIT}"
ln -sfn ../KernelSU-Next/kernel "${KERNEL_DIR}/drivers/kernelsu"

echo "[4/5] Applying POCO C40 + KernelSU-Next patch..."
if git -C "${KERNEL_DIR}" apply --check "${ROOT_DIR}/patches/0001-pococ40-kernelsu-next.patch" 2>/dev/null; then
    git -C "${KERNEL_DIR}" apply "${ROOT_DIR}/patches/0001-pococ40-kernelsu-next.patch"
else
    echo "Patch already applied (or clean check skipped)."
fi

export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
MAKE_ARGS=(
    -C "${KERNEL_DIR}"
    O="${OUT_DIR}"
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CC=clang
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    STRIP=llvm-strip
    LLVM=1
    LLVM_IAS=1
    KCFLAGS="-Wno-error -Wno-strict-prototypes -Wno-vla-extension"
)

echo "[5/5] Configuring & compiling Image.gz (-j${JOBS})..."
make "${MAKE_ARGS[@]}" gki_defconfig
(
    cd "${KERNEL_DIR}"
    ARCH=arm64 "${KERNEL_DIR}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
        "${OUT_DIR}/.config" \
        arch/arm64/configs/vendor/jr510_JGKI.config \
        arch/arm64/configs/vendor/jr510_JGKI-perfuser.config \
        "${ROOT_DIR}/configs/ksu-next.fragment"
)
make "${MAKE_ARGS[@]}" olddefconfig
make -j"${JOBS}" "${MAKE_ARGS[@]}" Image.gz

cp -f "${OUT_DIR}/arch/arm64/boot/Image.gz" "${ROOT_DIR}/Image.gz"
sha256sum "${ROOT_DIR}/Image.gz" > "${ROOT_DIR}/SHA256SUMS.txt"

echo ""
echo "Build succeeded!"
cat "${ROOT_DIR}/SHA256SUMS.txt"
