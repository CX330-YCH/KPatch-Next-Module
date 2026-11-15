# KPatch Next Module

Standalone implementation of KPM support for Magisk/KernelSU

## CX330 compatibility build

This fork packages [CX330-YCH/KPatch-Next](https://github.com/CX330-YCH/KPatch-Next)
with selected KernelPatch fixes and preserves the original Next KPM protocol.
See the core's `UPSTREAM_SYNC.md` for the exact upstream commits and exclusions.
The core remains 0.13.5 revision 3; this is not a full KernelPatch 0.13.9 port.

Requirements: Android ARM64 with an existing supported root manager,
`CONFIG_KALLSYMS_ALL=y`, and no built-in `CONFIG_KPM=y`. APatch is unsupported.
Installing this ZIP updates the management module and its tools. Updating the
running kernel core also requires patching the matching boot image and rebooting.
Keep a backup of the working boot image. The WebUI's export option creates an
image without writing the boot partition; the same choice applies to unpatching.

This build preserves failed KPM files, reports image/export/write failures, and
waits for KPM persistence before deleting temporary uploads. The upstream auto
update feed is removed from module metadata to avoid replacing this fork's core.

## Build and check

Use Node 22+, pnpm 10.28.2, Python 3, GitHub CLI, curl, zip/unzip and shasum.
Authenticate `gh` with an account that can download the pinned core artifact.

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/test_webui.mjs
bash build.sh
```

`version.properties` pins the core repository, source commit and build run.
`build.sh` verifies the artifact commit and SHA-256 manifest and the Magisk APK
checksum, builds the WebUI with its lockfile, checks ARM64 binaries, and creates
the ZIP and checksum under `out/`. `build-info.json` records the source and binary
hashes inside the module. Set `KPATCH_ASSET_DIR` to a downloaded core artifact
directory for a local build. GitHub Actions artifacts expire; if necessary, rerun
the core workflow at the pinned source and update the run ID.

CI compiles the core/tools/demo KPMs and runs malformed/legacy-image regressions.
Module CI runs script and WebUI regressions. Successful compilation and offline
image tests do not establish boot or arbitrary third-party KPM compatibility.

---

## Credits

- Patch scripts from [APatch](https://github.com/bmax121/APatch)
- KPatch-Next binaries from [KernelSU-Next/KPatch-Next](https://github.com/KernelSU-Next/KPatch-Next)
- magiskboot binary from [Magisk](https://github.com/topjohnwu/Magisk)

## License

- KPatch-Next-Module is licensed under GNU General Public License v3 [GPL-3.0](/LICENSE)
- KPatch-Next binaries is licensed under GNU General Public License v2 [GPL-2.0](https://www.gnu.org/licenses/gpl-2.0.html)
- magiskboot binary from Magisk is licenced under GNU General Public License v3 [GPL-3.0](https://github.com/topjohnwu/Magisk/blob/master/LICENSE)
- WebUI is licensed under MIT License [MIT](/webui/LICENSE)
