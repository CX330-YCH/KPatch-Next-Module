MODDIR="/data/adb/modules/KPatch-Next"

# Conflict with APatch
if [ "$APATCH" ]; then
    abort "! APatch is unsupported"
fi

# We only support arm64
if [ "$ARCH" != "arm64" ]; then
    abort "! Only arm64 is supported"
fi

set_perm_recursive "$MODPATH/bin" 0 2000 0755 0755

mkdir -p /data/adb/kp-next

# try get package_config from APatch
if [ -f "/data/adb/ap/package_config" ] && [ ! -f "/data/adb/kp-next/package_config" ]; then
    cp "/data/adb/ap/package_config" /data/adb/kp-next/package_config
fi

# backup module.prop
cp "$MODPATH/module.prop" "$MODPATH/module.prop.bak"

# Only hot-update an existing installation. On first install the manager will
# activate MODPATH at reboot; it may also install directly into MODDIR.
if [ -f "$MODDIR/module.prop" ] && [ "$MODPATH" != "$MODDIR" ]; then
    for dir in webroot bin patch; do
        mkdir -p "$MODDIR/$dir" || abort "! Cannot prepare $dir"
        cp -LRf "$MODPATH/$dir/." "$MODDIR/$dir/" || abort "! Cannot update $dir"
    done
fi
