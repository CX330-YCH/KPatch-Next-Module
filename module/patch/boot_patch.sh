#!/system/bin/sh
#######################################################################################
# APatch Boot Image Patcher
# Imported from https://github.com/bmax121/APatch/blob/main/app/src/main/assets/boot_patch.sh
#######################################################################################
#
# Usage: boot_patch.sh <bootimage> <true|false> [ARGS_PASS_TO_KPTOOLS]
#
# This script should be placed in a directory with the following files:
#
# File name          Type          Description
#
# boot_patch.sh      script        A script to patch boot image for APatch.
#                  (this file)      The script will use files in its same
#                                  directory to complete the patching process.
# bootimg            binary        The target boot image
# kpimg              binary        KernelPatch core Image
# kptools            executable    The KernelPatch tools binary to inject kpimg to kernel Image
# magiskboot         executable    Magisk tool to unpack boot.img.
#
#######################################################################################

MODPATH=${0%/*}
ARCH=$(getprop ro.product.cpu.abi)

# Load utility functions
. "$MODPATH/util_functions.sh"

[ "$#" -ge 1 ] || { echo "! Boot image is required" >&2; exit 1; }
BOOTIMAGE=$1
shift
FLASH_TO_DEVICE=${1:-false}
[ "$#" -eq 0 ] || shift
case "$FLASH_TO_DEVICE" in true|false) ;; *) echo "! Invalid flash mode" >&2; exit 1;; esac

[ -e "$BOOTIMAGE" ] || { >&2 echo "! $BOOTIMAGE does not exist"; exit 1; }

# Check for dependencies
command -v magiskboot >/dev/null 2>&1 || { >&2 echo "! Command magiskboot not found"; exit 1; }
command -v kptools >/dev/null 2>&1 || { >&2 echo "! Command kptools not found"; exit 1; }

# Re-read the requested boot image even after a failed/retried operation.
rm -f kernel kernel.ori new-boot.img
echo "- Unpacking boot image"
magiskboot unpack "$BOOTIMAGE" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    >&2 echo "! Unpack error: $?"
    exit 1
  fi

if kptools -i kernel -f | grep -q "CONFIG_KPM=y"; then
	echo "! Patcher has Aborted."
	echo "! Detected built-in KPM (CONFIG_KPM=y)."
	echo "! KPatch-Next is not compatible alongside built-in KPM."
	exit 1
fi

if ! kptools -i kernel -f | grep -q "^CONFIG_KALLSYMS_ALL=y$"; then
	echo "! Patcher has Aborted."
	echo "! KPatch-Next requires CONFIG_KALLSYMS_ALL to be Enabled."
	echo "! But your kernel seems NOT enabled it."
	exit 1
fi

if kptools -i kernel -l | grep -q "^patched=false$"; then
	echo "- Backing boot.img "
  cp "$BOOTIMAGE" "ori.img" || { echo "! Boot backup failed" >&2; exit 1; }
fi

mv kernel kernel.ori || exit 1

echo "- Patching kernel"

set -x
kptools -p -i kernel.ori -k kpimg -o kernel "$@"
patch_rc=$?
set +x

if [ $patch_rc -ne 0 ]; then
  >&2 echo "! Patch kernel error: $patch_rc"
  exit 1
fi

echo "- Repacking boot image"
magiskboot repack "$BOOTIMAGE" >/dev/null 2>&1

if [ $? -ne 0 ]; then
  >&2 echo "! Repack error: $?"
  exit 1
fi

[ -s new-boot.img ] || { echo "! Repack produced no boot image" >&2; exit 1; }

if [ "$FLASH_TO_DEVICE" = "true" ]; then
  if [ ! -b "$BOOTIMAGE" ] && [ ! -c "$BOOTIMAGE" ]; then
    echo "! Refusing to flash a non-device target; choose image export" >&2
    exit 1
  fi
  echo "- Flashing new boot image"
  if ! flash_image new-boot.img "$BOOTIMAGE"; then
    echo "! Flash failed" >&2
    save_image_to_storage "new-boot.img"
    exit 1
  fi
  echo "- Successfully Flashed!"
else
  save_image_to_storage "new-boot.img" || exit 1
  echo "- Successfully Patched!"
fi
