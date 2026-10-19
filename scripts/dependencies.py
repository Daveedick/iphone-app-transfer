#!/usr/bin/env python3
"""Check pinned developer inputs and collect full third-party license texts."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'vendor' / 'manifest.json'


def check():
    manifest = json.loads(MANIFEST.read_text())
    failures = []
    for component in manifest['native_libraries']:
        for item in component['binaries']:
            path = Path(item['developer_path'])
            if not path.is_file():
                failures.append(f'{component["name"]}: missing {path}')
            elif hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                failures.append(f'{component["name"]}: binary differs from pinned {component["version"]}; review/update vendor manifest deliberately')
    if not Path('/opt/homebrew/opt/libarchive/include/archive.h').is_file():
        failures.append('Missing libarchive development headers (runtime uses macOS system libarchive).')
    version = subprocess.check_output(['go', 'env', 'GOVERSION'], text=True).strip()
    try:
        major, minor = (int(x) for x in version.removeprefix('go').split('.')[:2])
        if (major, minor) < (1, 26):
            failures.append(f'Go 1.26 or newer required; found {version}')
    except ValueError:
        failures.append(f'Unrecognized Go version: {version}')
    if failures:
        raise RuntimeError('\n'.join(failures) + '\nSee vendor/manifest.json for exact source archives/checksums. No dependency is upgraded automatically.')
    print(f'Pinned native libraries verified; {version}.')


def json_objects(text):
    decoder = json.JSONDecoder()
    while text.strip():
        text = text.lstrip()
        value, consumed = decoder.raw_decode(text)
        yield value
        text = text[consumed:]


def notices(destination):
    destination.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text())
    for component in manifest['native_libraries']:
        directory = destination / component['name']
        directory.mkdir(exist_ok=True)
        for license_path in component['license_files']:
            source = Path(license_path)
            if not source.is_file():
                raise RuntimeError(f'Missing license text for {component["name"]}: {source}')
            shutil.copy2(source, directory / source.name)
        (directory / 'SOURCE.txt').write_text(f'{component["name"]} {component["version"]}\n{component["source_url"]}\nSHA-256: {component["source_sha256"]}\n')
    helper = ROOT / 'Helpers' / 'AppStoreBridge'
    environment = os.environ.copy()
    go_root = Path(environment.get('APP_TRANSFER_GO_ROOT', ROOT / '.build' / 'go'))
    environment.setdefault('GOPATH', str(go_root))
    environment.setdefault('GOMODCACHE', str(go_root / 'pkg' / 'mod'))
    environment.setdefault('GOCACHE', str(go_root / 'cache'))
    environment.setdefault('GOTOOLCHAIN', 'local')
    packages = subprocess.check_output(['go', 'list', '-mod=readonly', '-deps', '-json', './cmd/appstorebridge'], cwd=helper, text=True, env=environment)
    modules = {}
    for package in json_objects(packages):
        module = package.get('Module')
        if module:
            modules[module['Path']] = module
    summaries = []
    names = ('license', 'license.txt', 'license.md', 'copying', 'copying.txt', 'notice', 'notice.txt', 'notice.md')
    for module in sorted(modules.values(), key=lambda item: item['Path']):
        if module.get('Main'):
            continue
        resolved = module.get('Replace', module)
        directory = Path(resolved.get('Dir', ''))
        name = module['Path']
        version = module.get('Version', '')
        safe = name.replace('/', '_') + '@' + version
        target = destination / 'Go' / safe
        target.mkdir(parents=True, exist_ok=True)
        files = []
        if directory.is_dir():
            for source in directory.iterdir():
                if source.is_file() and source.name.lower() in names:
                    shutil.copy2(source, target / source.name)
                    files.append(source.name)
        # Keep missing metadata visible; do not silently claim license completeness.
        summaries.append({'module': name, 'version': version, 'license_files': files})
        (target / 'MODULE.txt').write_text(f'{name}\n{version}\nhttps://pkg.go.dev/{name}@{version}\n')
    (destination / 'go-modules.json').write_text(json.dumps(summaries, indent=2) + '\n')
    print(f'Included native licenses and notices for {len(summaries)} Go modules.')


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'check':
            check()
        elif sys.argv[1] == 'notices':
            notices(Path(sys.argv[2]))
        else:
            raise RuntimeError('Usage: dependencies.py check | notices DESTINATION')
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
