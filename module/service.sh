#!/bin/sh

MODDIR=${0%/*}
KPNDIR="/data/adb/kp-next"
PATH="$MODDIR/bin:$PATH"
CONFIG="$KPNDIR/package_config"
REHOOK="$(cat "$KPNDIR/rehook" 2>/dev/null)"

if [ -z "$(kpatch hello)" ]; then
    touch "$MODDIR/unresolved"
    exit 0
fi
rm -f "$MODDIR/unresolved"

for kpm in "$KPNDIR"/kpm/*.kpm; do
    [ -s "$kpm" ] || continue
    # A transient load failure must not delete the user's module. Disable its
    # next automatic load while retaining the file for diagnosis/recovery.
    if ! kpatch kpm load "$kpm"; then
        disabled="$kpm.disabled"
        while [ -e "$disabled" ]; do disabled="$disabled.disabled"; done
        mv "$kpm" "$disabled"
        echo "Failed to load $kpm; retained as $disabled" >&2
    fi
done

if [ -n "$REHOOK" ]; then
    if [ "$REHOOK" = "enable" ] || [ "$REHOOK" = "disable" ]; then
        kpatch rehook $REHOOK
    else
        rm -f "$KPNDIR/rehook"
    fi
fi

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

[ -f "$CONFIG" ] || exit 0

tail -n +2 "$CONFIG" | while IFS=, read -r pkg exclude allow uid; do
    if [ "$exclude" = "1" ]; then
        # priotize uid if exists
        UID=$(grep "^$pkg $uid" /data/system/packages.list | cut -d' ' -f2)
        # fallback to package name based
        [ -z "$UID" ] && UID=$(grep "^$pkg " /data/system/packages.list | cut -d' ' -f2)
        [ -n "$UID" ] && kpatch exclude_set "$UID" 1
    fi
done
