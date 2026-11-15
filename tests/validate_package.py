"""Reject incomplete module packages before distributing an installable ZIP."""
import pathlib
import struct
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
for relative in ('module.prop', 'customize.sh', 'service.sh', 'post-fs-data.sh',
                 'patch/boot_patch.sh', 'patch/boot_unpatch.sh', 'webroot/index.html'):
    path = root / relative
    assert path.is_file() and path.stat().st_size, f'Missing or empty: {path}'
for name in ('kpatch', 'kptools', 'magiskboot'):
    data = (root / 'bin' / name).read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01', f'{name} is not ELF64 little endian'
    assert struct.unpack_from('<H', data, 18)[0] == 183, f'{name} is not ARM64'
kpimg = (root / 'bin/kpimg').read_bytes()
assert len(kpimg) > 65536 and b'KP' in kpimg[:64], 'Invalid core image'
for path in root.rglob('*.sh'):
    subprocess.run(['sh', '-n', str(path)], check=True)
assert any((root/'webroot/assets').glob('*.js')), 'WebUI JavaScript is missing'
print('Package validation: ARM64 binaries, core, scripts and WebUI are present')
