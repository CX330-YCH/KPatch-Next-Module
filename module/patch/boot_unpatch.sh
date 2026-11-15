#!/system/bin/sh
#######################################################################################
# APatch Boot Image Unpatcher
# Imported from https://github.com/bmax121/APatch/blob/main/app/src/main/assets/boot_unpatch.sh
#######################################################################################

MODPATH=${0%/*}
ARCH=$(getprop ro.product.cpu.abi)

# Load utility functions
. "$MODPATH/util_functions.sh"

BOOTIMAGE=$1
FLASH_TO_DEVICE=${2:-false}
case "$FLASH_TO_DEVICE" in true|false) ;; *) echo "! Invalid flash mode" >&2; exit 1;; esac

[ -e "$BOOTIMAGE" ] || { echo "! $BOOTIMAGE does not exist" >&2; exit 1; }
command -v magiskboot >/dev/null 2>&1 || { echo "! magiskboot not found" >&2; exit 1; }
command -v kptools >/dev/null 2>&1 || { echo "! kptools not found" >&2; exit 1; }

# Never restore an unrelated or previously patched new-boot.img.
rm -f kernel kernel.ori new-boot.img
magiskboot unpack "$BOOTIMAGE" || exit 1
kernel_info=$(kptools -i kernel -l) || exit 1
if ! printf '%s\n' "$kernel_info" | grep -q '^patched=true$'; then
  echo "! Kernel is not patched" >&2
  exit 1
fi

mv kernel kernel.ori || exit 1
echo "- Unpatching kernel"
kptools -u --image kernel.ori --out kernel || exit 1
magiskboot repack "$BOOTIMAGE" || exit 1
[ -s new-boot.img ] || { echo "! Repack produced no boot image" >&2; exit 1; }

if [ "$FLASH_TO_DEVICE" = "true" ]; then
  if [ ! -b "$BOOTIMAGE" ] && [ ! -c "$BOOTIMAGE" ]; then
    echo "! Refusing to flash a non-device target; choose image export" >&2
    exit 1
  fi
  if ! flash_image new-boot.img "$BOOTIMAGE"; then
    echo "! Flash failed" >&2
    save_image_to_storage "new-boot.img"
    exit 1
  fi
  echo "- Successfully Flashed!"
else
  save_image_to_storage "new-boot.img" || exit 1
  echo "- Successfully Unpatched!"
fi
