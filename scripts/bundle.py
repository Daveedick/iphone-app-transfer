#!/usr/bin/env python3
"""Bundle a closed Mach-O dependency graph and verify its relocatability."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

PROJECT = Path(__file__).resolve().parent.parent


def source_digest():
    files = [PROJECT / 'Package.swift', PROJECT / 'vendor' / 'manifest.json']
    files += [p for p in (PROJECT / 'Sources').rglob('*') if p.suffix in ('.swift', '.c', '.h', '.strings')]
    files += [p for p in (PROJECT / 'Helpers' / 'AppStoreBridge').rglob('*') if p.suffix in ('.go', '.mod', '.sum') and not p.name.endswith('_test.go')]
    files += [PROJECT / 'scripts' / name for name in ('build-app.sh', 'bundle.py', 'dependencies.py', 'IconRenderer.swift', 'make-icon.py')]
    digest = hashlib.sha256()
    for path in sorted(set(files)):
        digest.update(str(path.relative_to(PROJECT)).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def dependencies(path):
    lines = run('/usr/bin/otool', '-L', str(path)).splitlines()[1:]
    return [line.strip().split(' (compatibility version', 1)[0] for line in lines if line.strip()]


def system_library(name):
    return name.startswith(('/usr/lib/', '/System/Library/')) or name.startswith('@rpath/libswift')


def macho_files(app):
    for directory in ('MacOS', 'Helpers', 'Frameworks'):
        root = app / 'Contents' / directory
        for path in root.rglob('*'):
            if path.is_file() and 'Mach-O' in run('/usr/bin/file', '-b', str(path)):
                yield path


def rpaths(path):
    return re.findall(r'\bpath (.*?) \(offset \d+\)', run('/usr/bin/otool', '-l', str(path)))


def prepare(app, version, build):
    frameworks = app / 'Contents' / 'Frameworks'
    frameworks.mkdir(parents=True, exist_ok=True)
    originals = {}
    hashes = []
    pending = list(macho_files(app))
    visited = set()
    while pending:
        binary = pending.pop(0)
        if binary in visited:
            continue
        visited.add(binary)
        changes = []
        for dependency in dependencies(binary):
            if system_library(dependency):
                continue
            if dependency.startswith(('@loader_path/', '@executable_path/')):
                continue
            if dependency.startswith('@rpath/'):
                target = frameworks / Path(dependency).name
                if target.exists():
                    continue
                raise RuntimeError(f'Unresolved runtime dependency {dependency} in {binary.name}')
            if not dependency.startswith(('/opt/homebrew/', '/usr/local/')):
                raise RuntimeError(f'Unexpected non-system dependency {dependency}')
            source = Path(dependency).resolve(strict=True)
            target = frameworks / source.name
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            if target.name in originals and originals[target.name] != source:
                raise RuntimeError(f'Dependency filename collision: {target.name}')
            if not target.exists():
                shutil.copy2(source, target)
                target.chmod(0o755)
                originals[target.name] = source
                hashes.append({'file': target.name, 'source_sha256': digest})
                run('/usr/bin/install_name_tool', '-id', '@rpath/' + target.name, str(target))
                pending.append(target)
            replacement = ('@loader_path/' if binary.parent == frameworks else '@rpath/') + target.name
            changes.append((dependency, replacement))
        for old, new in changes:
            run('/usr/bin/install_name_tool', '-change', old, new, str(binary))
        if binary.parent != frameworks:
            desired = '@executable_path/../Frameworks'
            if desired not in rpaths(binary):
                run('/usr/bin/install_name_tool', '-add_rpath', desired, str(binary))
        # Remove SwiftPM's absolute build rpath rather than relying on fallback.
        for value in rpaths(binary):
            if value.startswith('/') and not value.startswith(('/usr/lib/', '/System/Library/')):
                run('/usr/bin/install_name_tool', '-delete_rpath', value, str(binary))
    info = {
        'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'ru'],
        'CFBundleDisplayName': 'iPhone App Transfer', 'CFBundleName': 'iPhone App Transfer',
        'CFBundleExecutable': 'AppTransfer', 'CFBundleIdentifier': 'app.apptransfer.desktop',
        'CFBundleInfoDictionaryVersion': '6.0', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version, 'CFBundleVersion': build,
        'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': '15.0',
        'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
        'NSHumanReadableCopyright': 'iPhone App Transfer contributors. Third-party notices included.',
    }
    (app / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info))
    resources = app / 'Contents' / 'Resources'
    (resources / 'bundled-libraries.json').write_text(json.dumps(hashes, indent=2) + '\n')
    build_info = {'source_sha256': source_digest(), 'configuration': os.environ.get('CONFIGURATION', 'release'), 'swift': run('/usr/bin/xcrun', 'swift', '--version').strip()}
    (resources / 'build-information.json').write_text(json.dumps(build_info, indent=2) + '\n')
    verify(app)


def version_tuple(value):
    return tuple(int(piece) for piece in value.split('.'))


def verify(app):
    app = app.resolve(strict=True)
    issues = []
    frameworks = app / 'Contents' / 'Frameworks'
    for required in ('Contents/MacOS/AppTransfer', 'Contents/Helpers/AppStoreBridge', 'Contents/Resources/AppIcon.icns', 'Contents/Info.plist'):
        if not (app / required).is_file():
            issues.append(f'Missing required bundle file: {required}')
    info_path = app / 'Contents' / 'Info.plist'
    if info_path.is_file():
        info = plistlib.loads(info_path.read_bytes())
        if info.get('CFBundleExecutable') != 'AppTransfer' or info.get('LSMinimumSystemVersion') != '15.0':
            issues.append('Bundle executable/minimum macOS metadata does not match the MVP target')
    files = list(macho_files(app))
    if not files:
        raise RuntimeError('The app contains no Mach-O executables.')
    for binary in files:
        architectures = run('/usr/bin/lipo', '-archs', str(binary)).strip().split()
        if 'arm64' not in architectures:
            issues.append(f'{binary.name}: arm64 is missing')
        build = run('/usr/bin/vtool', '-show-build', str(binary))
        minimum = re.findall(r'\bminos\s+(\d+(?:\.\d+)+)', build)
        if not minimum:
            # Older LC_VERSION_MIN_MACOSX load commands.
            minimum = re.findall(r'\bversion\s+(\d+(?:\.\d+)+)', build)
        if minimum and any(version_tuple(v) > (15, 0, 0) for v in minimum):
            issues.append(f'{binary.name}: requires macOS {minimum}')
        for dependency in dependencies(binary):
            if system_library(dependency):
                continue
            if dependency.startswith('@rpath/'):
                target = frameworks / Path(dependency).name
            elif dependency.startswith('@loader_path/'):
                target = binary.parent / dependency[len('@loader_path/'):]
            elif dependency.startswith('@executable_path/'):
                target = binary.parent / dependency[len('@executable_path/'):]
            else:
                issues.append(f'{binary.name}: absolute dependency {dependency}')
                continue
            if not target.exists() or not target.resolve().is_relative_to(app):
                issues.append(f'{binary.name}: missing/outside-bundle dependency {dependency}')
        for value in rpaths(binary):
            if value.startswith('/') and not value.startswith(('/usr/lib/', '/System/Library/')):
                issues.append(f'{binary.name}: developer rpath {value}')
    if issues:
        raise RuntimeError('\n'.join(issues))
    print(f'Verified {len(files)} Mach-O files; dependency graph is inside app/system.')


if __name__ == '__main__':
    try:
        if sys.argv[1] == '--source-digest':
            print(source_digest())
        elif sys.argv[1] == '--verify':
            verify(Path(sys.argv[2]))
        else:
            prepare(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
