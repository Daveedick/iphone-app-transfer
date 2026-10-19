#!/usr/bin/env python3
"""Render the project-native icon, then build a standard macOS ICNS."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

destination = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parent.parent
module_cache = root / '.build' / 'icon-module-cache'
module_cache.mkdir(parents=True, exist_ok=True)
environment = os.environ.copy()
environment['CLANG_MODULE_CACHE_PATH'] = str(module_cache)
overlay = subprocess.check_output(['python3', str(root / 'scripts' / 'prepare-toolchain.py')], text=True).strip()
with tempfile.TemporaryDirectory(prefix='app-transfer-icon-', dir=root / '.build') as tmp:
    directory = Path(tmp)
    source = directory / 'source.png'
    subprocess.run(['xcrun', 'swift', '-module-cache-path', str(module_cache), '-vfsoverlay', overlay, '-Xcc', '-ivfsoverlay', '-Xcc', overlay, str(root / 'scripts' / 'IconRenderer.swift'), str(source)], check=True, env=environment)
    iconset = directory / 'AppIcon.iconset'
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            path = iconset / f'icon_{size}x{size}{suffix}.png'
            pixels = str(size * scale)
            subprocess.run(['/usr/bin/sips', '-z', pixels, pixels, str(source), '--out', str(path)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(iconset), '-o', str(destination)], check=True)
