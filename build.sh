#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ${1:-} == clean ]]; then
    rm -rf out module/bin module/webroot
    exit 0
fi
get_ver() {
    awk -F= -v key="$1" '$1 == key {gsub(/"/, "", $2); print $2}' version.properties
}
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
for tool in gh curl unzip zip python3 shasum; do
    command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
core_repo=$(get_ver kpatch-repository)
core_commit=$(get_ver kpatch-commit)
core_run=$(get_ver kpatch-run)
[[ $core_commit =~ ^[0-9a-f]{40}$ ]] || { echo 'Pin a full core commit in version.properties' >&2; exit 1; }
mkdir -p out module/bin
work=$(mktemp -d "${TMPDIR:-/tmp}/kpatch-build.XXXXXX")
trap 'rm -rf "$work"' EXIT
assets=${KPATCH_ASSET_DIR:-$work/core}
if [[ -z ${KPATCH_ASSET_DIR:-} ]]; then
    gh run download "$core_run" --repo "$core_repo" --name "kpatch-next-core-$core_commit" --dir "$assets"
fi
[[ $(cat "$assets/SOURCE_COMMIT") == "$core_commit" ]] || { echo 'Core source commit mismatch' >&2; exit 1; }
(cd "$assets" && shasum -a 256 -c SHA256SUMS)
cp "$assets/kpatch-android" module/bin/kpatch
cp "$assets/kptools-android" module/bin/kptools
cp "$assets/kpimg-linux" module/bin/kpimg
magisk_version=$(get_ver magiskboot)
curl --fail --location --retry 3 "https://github.com/topjohnwu/Magisk/releases/download/$magisk_version/Magisk-$magisk_version.apk" --output "$work/magisk.apk"
[[ $(sha256 "$work/magisk.apk") == "$(get_ver magisk-apk-sha256)" ]] || { echo 'Magisk APK checksum mismatch' >&2; exit 1; }
unzip -p "$work/magisk.apk" lib/arm64-v8a/libmagiskboot.so > module/bin/magiskboot
chmod 0755 module/bin/* module/*.sh module/patch/*.sh
(
    cd webui
    "${PNPM_BIN:-pnpm}" install --frozen-lockfile
    "${PNPM_BIN:-pnpm}" build
)
python3 tests/validate_package.py module
version=$(sed -n 's/^version=//p' module/module.prop)
commit=$(git rev-parse HEAD)
python3 - "$core_repo" "$core_commit" "$core_run" "$commit" <<'PYINFO'
import hashlib, json, pathlib, sys
module = pathlib.Path('module')
manifest = {
    'core_repository': sys.argv[1], 'core_commit': sys.argv[2], 'core_build_run': sys.argv[3],
    'module_commit': sys.argv[4],
    'binaries': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((module/'bin').iterdir())},
}
(module/'build-info.json').write_text(json.dumps(manifest, indent=2)+'\n')
PYINFO
archive="KPatch-Next-$version.zip"
rm -f "out/$archive"
(cd module && zip -q -r "../out/$archive" . -x 'tmp/*' 'ori.img' 'new-boot.img' '*.log' 'module.prop.bak')
(cd out && shasum -a 256 "$archive" > "$archive.sha256")
echo "Built: out/$archive"
