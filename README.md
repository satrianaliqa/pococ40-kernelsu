# POCO C40 (`frost`) — KernelSU-Next (Linux 5.4.242)

Source build-kit, patch, dan prebuilt kernel image **KernelSU-Next** untuk **POCO C40 (`frost` / JLQ JR510, Android 11 / MIUI)**.

Repositori ini dibuat agar siapa pun dapat:
1. **Mengunduh binary `Image.gz` siap pakai** di halaman [Releases](../../releases), atau
2. **Mengompilasi ulang sendiri secara bersih dan deterministik** menggunakan `build.sh` maupun GitHub Actions.

---

## Spesifikasi & Fitur Kernel

| Komponen | Detail |
|---|---|
| **Device** | POCO C40 (`frost`) — JLQ JR510 (`aarch64`) |
| **Base Kernel** | `MiCode/Xiaomi_Kernel_OpenSource` branch `frost-r-oss` (`Linux 5.4.242`) |
| **Toolchain** | AOSP `clang-r416183b` (Clang 12.0.5 + LLD 12.0.5, `LLVM=1 LLVM_IAS=1`) |
| **Root Solution** | `KernelSU-Next` commit `e3292239` (`33313`, **UAPI v5**) + **SUSFS v2.4.0** |
| **Manager APK** | Kompatibel dengan **KernelSU-Next Manager v3.4.2 (`33355-5`)** |
| **Hook Mode** | `CONFIG_KSU_MANUAL_HOOK=y` (Manual Hook) |
| **Root Hiding** | `CONFIG_KSU_SUSFS=y` (`SUS_PATH`, `SUS_MOUNT`, `SUS_KSTAT`, `SPOOF_UNAME`, `SPOOF_CMDLINE_OR_BOOTCONFIG`, `HIDE_KSU_SUSFS_SYMBOLS`, `OPEN_REDIRECT`, `SUS_MAP`, `PRIORITY_UID_FILTER`, `ENABLE_LOG`) |
| **Metamodule Support** | `CONFIG_OVERLAY_FS=y`, `CONFIG_TMPFS_XATTR=y`, `CONFIG_TMPFS_POSIX_ACL=y` |
| **Debug Log** | `CONFIG_KSU_DEBUG=n` (bebas spam log di `dmesg`) |

### Apa saja yang sudah di-patch?

1. **KernelSU-Next Manual Hooks**
   - `KSU_SYSCALL_TABLE_HOOK` gagal di kernel JR510 (`sth: 0/4 syscalls hooked`), sehingga digunakan **Manual Hook** (`CONFIG_KSU_MANUAL_HOOK=y`) pada:
     - `kernel/reboot.c` (`ksu_handle_sys_reboot`)
     - `kernel/seccomp.c` (mengizinkan `__NR_reboot` dengan magic `0xDEADBEEF` melewati `__secure_computing`)
     - `fs/exec.c` (`ksu_handle_execveat`)
     - `fs/open.c` (`ksu_handle_faccessat`)
     - `fs/stat.c` (`ksu_handle_stat`)
     - `drivers/input/input.c` (`ksu_handle_input_handle_event`)
2. **Kompatibilitas Modul Vendor Stock (`5.4.219` → `5.4.242`)**
   - Mengaktifkan `CONFIG_SHADOW_CALL_STACK=y` dan `CONFIG_SHADOW_CALL_STACK_VMAP=y` serta patch `vermagic`/CRC di `kernel/module.c` agar seluruh modul prebuilt `.ko` di `vendor_boot` (`mali_kbase`, `wlan`, `camera`, `jlq_ion_heaps_dlkm`, dll.) tetap termuat sempurna.
3. **Tanpa Spam `dmesg`**
   - `CONFIG_KSU_DEBUG=n` membuat `dmesg` tetap bersih.
   - **Catatan `adb shell su`:** Karena mode non-debug tidak otomatis memberi akses root ke `Shell (uid=2000)`, aktifkan toggle **Shell** di tab **Superuser** pada **KernelSU-Next Manager** jika ingin menggunakan `adb shell su`.
4. **Auto-Retry Wi-Fi Probe (`icnss2`)**
   - Menambahkan mekanisme delayed retry probe di `drivers/soc/qcom/icnss2/` agar modul `qca_cld3_wlan.ko` bawaan ROM stock otomatis di-probe ulang saat boot jika gagal inisialisasi awal akibat race condition.
5. **SUSFS v2.4.0 & Dukungan Metamodule**
   - Mengintegrasikan `susfs4ksu` **v2.4.0** ke kernel Linux `5.4.242` (`include/linux/susfs*.h`, `fs/susfs.c`, VFS/proc/namespace/selinux hooks) dan `KernelSU-Next` tanpa mengubah layout struct KABI agar modul `.ko` stock `5.4.219` tetap kompatibel.
   - Mengaktifkan `CONFIG_OVERLAY_FS=y`, `CONFIG_TMPFS_XATTR=y`, dan `CONFIG_TMPFS_POSIX_ACL=y` untuk dukungan metamodule (`meta-overlayfs` / `magic_mount`).

---

## Cara Menggunakan Prebuilt `Image.gz` (Flash via TWRP + `magiskboot`)

> [!WARNING]
> **Selalu backup partisi `boot` Anda terlebih dahulu!**
> Boot image POCO C40 menggunakan Android Boot Header v3 dengan ramdisk `lz4_legacy` (atau TWRP ramdisk jika sudah terpasang). **Jangan** gunakan `fastboot boot` karena tidak didukung bootloader JR510.

1. Unduh `Image.gz` (dan cek `SHA256SUMS.txt`) dari halaman [Releases](../../releases).
2. Masuk ke **TWRP** dan hubungkan HP ke PC via ADB, lalu backup `boot_a` (atau slot aktif Anda):
   ```bash
   adb shell "dd if=/dev/block/by-name/boot_a of=/tmp/boot_orig.img bs=4096"
   adb pull /tmp/boot_orig.img ./boot_backup.img
   ```
3. Push `Image.gz` ke `/tmp/` di TWRP, repack memakai `magiskboot`, lalu flash kembali ke `boot_a`:
   ```bash
   adb push Image.gz /tmp/Image.gz
   adb shell "
     mkdir -p /tmp/repack && cd /tmp/repack &&
     magiskboot unpack /tmp/boot_orig.img &&
     cp /tmp/Image.gz kernel &&
     magiskboot repack /tmp/boot_orig.img new_boot.img &&
     dd if=new_boot.img of=/dev/block/by-name/boot_a bs=4096 &&
     sync
   "
   adb reboot
   ```
4. Setelah masuk Android, install **KernelSU-Next Manager v3.4.2 (`33355-5`)**.

---

## Cara Compile Sendiri (Local Build)

Pastikan dependensi build kernel Linux standar tersedia (`git`, `curl`, `bc`, `bison`, `flex`, `make`, `python3`, `libssl-dev`, `libelf-dev`, `cpio`).

```bash
git clone https://github.com/satrianaliqa/pococ40-kernelsu.git
cd pococ40-kernelsu
chmod +x build.sh
./build.sh
```

Script `build.sh` akan otomatis:
1. Mengunduh toolchain AOSP `clang-r416183b` ke `./toolchain/` (jika belum ada).
2. Meng-clone `MiCode/Xiaomi_Kernel_OpenSource` (`frost-r-oss`, `--depth=1`) ke `./work/kernel/`.
3. Meng-clone `KernelSU-Next` di commit `e3292239` (UAPI v5).
4. Menerapkan `patches/0001-pococ40-kernelsu-next.patch`, `patches/0002-kernelsu-next-susfs.patch`, dan `configs/ksu-next.fragment`.
5. Menghasilkan `./Image.gz` dan `./SHA256SUMS.txt`.

### Build via GitHub Actions (Opsional)

Repo ini juga menyertakan workflow [`.github/workflows/build.yml`](.github/workflows/build.yml). Anda dapat mem-fork repo ini lalu menjalankan workflow **Build POCO C40 KernelSU-Next** secara manual melalui tab **Actions → Run workflow** untuk mendapatkan artifact `Image.gz`.

---

## Struktur Repositori

```text
.
├── .github/workflows/build.yml         # GitHub Actions build workflow (opsional)
├── configs/ksu-next.fragment           # Konfigurasi KernelSU-Next, SUSFS & Shadow Call Stack
├── patches/
│   ├── 0001-pococ40-kernelsu-next.patch # Patch kernel Manual Hook, SUSFS v2.4.0 & vendor compat
│   └── 0002-kernelsu-next-susfs.patch   # Patch integrasi SUSFS v2.4.0 untuk KernelSU-Next
├── build.sh                            # Script build lokal otomatis
└── README.md
```

## Lisensi

Mengikuti lisensi kernel Linux ([GPL-2.0](LICENSE)).
