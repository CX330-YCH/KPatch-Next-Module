"""Host-side regression tests. All Android commands and flash operations are mocked."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.commands = self.base / 'commands'
        self.commands.mkdir()
        self.work = self.base / 'work'
        self.work.mkdir()
        self.env = dict(os.environ, PATH=f'{self.commands}:{os.environ["PATH"]}')
        self.command('getprop', 'echo 1')

    def command(self, name, body):
        p = self.commands / name
        p.write_text('#!/bin/sh\n' + body + '\n')
        p.chmod(0o755)
        return p

    def run_shell(self, command, **env):
        return subprocess.run(['sh', '-c', command], cwd=self.work,
                              env={**self.env, **env}, text=True, capture_output=True)

    def prepare_boot(self):
        patch = self.base / 'patch'
        patch.mkdir()
        for name in ['boot_patch.sh', 'boot_unpatch.sh']:
            shutil.copyfile(ROOT / 'module/patch' / name, patch / name)
        (patch / 'util_functions.sh').write_text('''
flash_image() { echo flash >> calls; return "${FLASH_FAIL:-0}"; }
save_image_to_storage() {
    [ "${SAVE_FAIL:-0}" = 0 ] || return 1
    cp "$1" saved.img
}
''')
        self.command('magiskboot', '''
case "$1" in
unpack) echo unpack >> calls; [ "${UNPACK_FAIL:-0}" = 0 ] || exit 7; echo fresh-kernel > kernel;;
repack) echo repack >> calls; [ "${REPACK_FAIL:-0}" = 0 ] || exit 8;
  [ "${EMPTY_REPACK:-0}" = 0 ] && cp kernel new-boot.img; exit 0;;
esac
''')
        self.command('kptools', '''
case " $* " in
*" -f "*) echo CONFIG_KALLSYMS_ALL=y; [ "${BUILTIN_KPM:-0}" = 0 ] || echo CONFIG_KPM=y;;
*" -l "*) echo "patched=${PATCHED:-false}";;
*" -u "*) echo unpatch >> calls; echo restored-kernel > kernel;;
*" -p "*) echo patch >> calls; [ "${PATCH_FAIL:-0}" = 0 ] || exit 9; echo patched-kernel > kernel;;
esac
exit 0
''')
        (self.work / 'boot.img').write_text('original-boot')
        (self.work / 'kpimg').write_text('core')
        return patch

    def test_first_install_does_not_create_partial_live_module(self):
        live = self.base / 'data/adb/modules/KPatch-Next'
        staged = self.base / 'staged'
        for d in ['bin', 'patch', 'webroot']:
            (staged / d).mkdir(parents=True)
            (staged / d / 'payload').write_text(d)
        (staged / 'module.prop').write_text('id=KPatch-Next\n')
        script = self.base / 'customize.sh'
        script.write_text((ROOT / 'module/customize.sh').read_text().replace('/data/adb', str(self.base / 'data/adb')))
        result = self.run_shell(f'set_perm_recursive() {{ :; }}; abort() {{ exit 1; }}; . "{script}"', MODPATH=str(staged), ARCH='arm64')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(live.exists())
        self.assertTrue((staged / 'bin/payload').exists())

    def test_direct_install_does_not_delete_its_own_payload(self):
        live = self.base / 'data/adb/modules/KPatch-Next'
        for d in ['bin', 'patch', 'webroot']:
            (live / d).mkdir(parents=True)
            (live / d / 'payload').write_text(d)
        (live / 'module.prop').write_text('id=KPatch-Next\n')
        script = self.base / 'customize.sh'
        script.write_text((ROOT / 'module/customize.sh').read_text().replace('/data/adb', str(self.base / 'data/adb')))
        result = self.run_shell(f'set_perm_recursive() {{ :; }}; abort() {{ exit 1; }}; . "{script}"', MODPATH=str(live), ARCH='arm64')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((live / 'bin/payload').exists())

    def test_failed_autoload_preserves_module_bytes(self):
        persistent = self.base / 'data/adb/kp-next/kpm'
        persistent.mkdir(parents=True)
        (persistent / 'example.kpm').write_bytes(b'keep-me')
        self.command('kpatch', 'case "$1" in hello) echo hello;; kpm) exit 1;; esac')
        script = self.base / 'service.sh'
        script.write_text((ROOT / 'module/service.sh').read_text().replace('/data/adb', str(self.base / 'data/adb')))
        self.run_shell(f'sh "{script}"')
        self.assertEqual((persistent / 'example.kpm.disabled').read_bytes(), b'keep-me')

    def test_patch_export_does_not_flash(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img false')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / 'saved.img').read_text().strip(), 'patched-kernel')
        self.assertNotIn('flash', (self.work / 'calls').read_text())
        self.assertEqual((self.work / 'boot.img').read_text(), 'original-boot')

    def test_unpatch_export_regenerates_stale_image(self):
        patch = self.prepare_boot()
        (self.work / 'new-boot.img').write_text('stale-patched-image')
        result = self.run_shell(f'sh "{patch}/boot_unpatch.sh" boot.img false', PATCHED='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / 'saved.img').read_text().strip(), 'restored-kernel')
        self.assertNotIn('flash', (self.work / 'calls').read_text())

    def test_unpatch_defaults_to_export(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_unpatch.sh" boot.img', PATCHED='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('flash', (self.work / 'calls').read_text())

    def test_failed_patch_cannot_repack_or_flash(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img true', PATCH_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        calls = (self.work / 'calls').read_text()
        self.assertNotIn('repack', calls)
        self.assertNotIn('flash', calls)

    def test_empty_repack_cannot_succeed(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img false', EMPTY_REPACK='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / 'saved.img').exists())

    def test_builtin_kpm_is_rejected(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img false', BUILTIN_KPM='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('patch\n', (self.work / 'calls').read_text().replace('unpack', ''))

    def test_save_failure_is_reported(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img false', SAVE_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Successfully', result.stdout)

    def test_regular_file_is_not_silently_flashed(self):
        patch = self.prepare_boot()
        result = self.run_shell(f'sh "{patch}/boot_patch.sh" boot.img true')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('flash\n', (self.work / 'calls').read_text())

    def test_flash_helper_propagates_write_failure(self):
        (self.work / 'image').write_text('image')
        result = self.run_shell(f'. "{ROOT}/module/patch/util_functions.sh"; flash_image image "missing/target"')
        self.assertNotEqual(result.returncode, 0)

    def test_flash_helper_propagates_nandwrite_failure(self):
        # /dev/null is only used for its character-device type. Neither mock
        # executes any writes to the device.
        (self.work / 'image').write_text('image')
        self.command('flash_eraseall', 'exit 0')
        self.command('nandwrite', 'exit 9')
        result = self.run_shell(f'. "{ROOT}/module/patch/util_functions.sh"; flash_image image /dev/null')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
