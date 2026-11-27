#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

usage() {
    echo "Usage: $0 [--package-only] [release-dir]" >&2
}

package_only=0
target_dir=""
has_target_dir=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-only)
            package_only=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            if [[ "$has_target_dir" -eq 1 ]]; then
                usage
                exit 1
            fi
            target_dir="$1"
            has_target_dir=1
            shift
            ;;
    esac
done

python3 - "$package_only" "$target_dir" <<'PY'
import base64
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile


def require(condition, message):
    if not condition:
        raise SystemExit(message)


package_only = sys.argv[1] == '1'
target_dir = sys.argv[2]

info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
directory = Path(target_dir or f'dist/{version}')
archive = directory / f'ViveBrush-{version}-arm64.app.zip'
dmg = directory / f'ViveBrush-{version}-arm64.dmg'
sums_file = directory / 'SHA256SUMS.txt'
require(dmg.is_file(), f'Missing packaged DMG: {dmg}')
require(archive.is_file(), f'Missing packaged app ZIP: {archive}')
require(sums_file.is_file(), f'Missing checksums file: {sums_file}')

if package_only:
    names = {archive.name, dmg.name}
    expected_count = 2
    count_message = 'Expected checksums for exactly the DMG and app ZIP.'
else:
    feed = directory / 'appcast.xml'
    require(feed.is_file(), f'Missing signed appcast: {feed}')
    names = {archive.name, dmg.name, feed.name}
    expected_count = 3
    count_message = 'Expected checksums for exactly the DMG, app ZIP, and signed feed.'

lines = sums_file.read_text().splitlines()
require(len(lines) == expected_count, count_message)
checked = set()
for line in lines:
    require('  ' in line, f'Malformed checksum line: {line}')
    digest, name = line.split('  ', 1)
    require(name in names and name not in checked, 'Unexpected or duplicate checksum entry.')
    require(hashlib.sha256((directory / name).read_bytes()).hexdigest() == digest, f'Checksum mismatch: {name}')
    checked.add(name)

with zipfile.ZipFile(archive) as package:
    namelist = package.namelist()
    require(len(namelist) == len(set(namelist)), 'Duplicate entries in app ZIP.')
    require('ViveBrush.app/Contents/Info.plist' in namelist, 'Packaged app is missing Info.plist.')
    if Path('Resources/AppIcon.png').is_file():
        icon_entry = 'ViveBrush.app/Contents/Resources/AppIcon.icns'
        require(icon_entry in namelist, 'Packaged app is missing AppIcon.icns.')
        require(package.getinfo(icon_entry).file_size > 0, 'Packaged AppIcon.icns is empty.')
    packaged = plistlib.loads(package.read('ViveBrush.app/Contents/Info.plist'))

for key in (
    'CFBundleIdentifier',
    'CFBundleShortVersionString',
    'CFBundleVersion',
    'CFBundleIconFile',
    'SUPublicEDKey',
    'SUFeedURL',
    'LSMinimumSystemVersion',
    'SURequireSignedFeed',
    'SUVerifyUpdateBeforeExtraction',
):
    require(packaged.get(key) == info.get(key), f'Packaged metadata mismatch: {key}')
require(
    packaged.get('SURequireSignedFeed') is True and packaged.get('SUVerifyUpdateBeforeExtraction') is True,
    'Signed feed and archive validation must be enabled.',
)
public_key = packaged['SUPublicEDKey']
require(len(base64.b64decode(public_key, validate=True)) == 32, 'Invalid update public key.')

if not package_only:
    data = feed.read_bytes()
    content, marker, block = data.rpartition(b'<!-- sparkle-signatures:\n')
    require(bool(marker) and b'-->' in block, 'Missing embedded feed signature.')
    fields = dict(line.split(':', 1) for line in block.split(b'-->', 1)[0].decode().splitlines() if ':' in line)
    require(int(fields.get('length', '-1')) == len(content), 'Signed feed length mismatch.')
    sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    root = ET.fromstring(content)
    items = root.findall('./channel/item')
    require(len(items) == 1, 'Expected exactly one release item.')
    item = items[0]
    require(item.findtext(sparkle + 'version') == packaged['CFBundleVersion'], 'Feed build number mismatch.')
    require(item.findtext(sparkle + 'shortVersionString') == version, 'Feed display version mismatch.')
    require(item.findtext(sparkle + 'hardwareRequirements') == 'arm64', 'Feed must target Apple Silicon.')
    require(bool((item.findtext('description') or '').strip()), 'Feed item description is empty.')
    enclosure = item.find('enclosure')
    require(enclosure is not None, 'Missing update enclosure.')
    url = urlsplit(enclosure.attrib['url'])
    require(
        url.hostname and url.username is None and url.password is None and not url.fragment and
        (url.scheme == 'https' or (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost'))),
        'Invalid download URL.',
    )
    require(url.path.rsplit('/', 1)[-1] == archive.name, 'Download URL filename mismatch.')
    require(int(enclosure.attrib['length']) == archive.stat().st_size, 'Archive length mismatch.')

with tempfile.TemporaryDirectory(prefix='vivebrush-verify-') as temporary:
    temporary = Path(temporary)
    if not package_only:
        verifier = temporary / 'verify-signature'
        subprocess.run(['swiftc', 'scripts/verify-signature.swift', '-o', str(verifier)], check=True)
        signed_content = temporary / 'feed-content.xml'
        signed_content.write_bytes(content)
        subprocess.run([str(verifier), public_key, str(signed_content), fields['edSignature'].strip()], check=True)
        subprocess.run([str(verifier), public_key, str(archive), enclosure.attrib[sparkle + 'edSignature']], check=True)
    subprocess.run(['ditto', '-x', '-k', str(archive), str(temporary)], check=True)
    app = temporary / 'ViveBrush.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    architecture = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/ViveBrush')], text=True).strip()
    require(architecture == 'arm64', 'Expected an arm64-only executable.')

if package_only:
    print(f'PASS: ViveBrush {version} ({packaged["CFBundleVersion"]}) — package-only checksums, metadata, bundle signature, arm64')
else:
    print(f'PASS: ViveBrush {version} ({packaged["CFBundleVersion"]}) — checksums, public-key feed/ZIP signatures, bundle signature, arm64')
PY
