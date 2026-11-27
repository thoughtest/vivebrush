#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

usage() {
    echo "Usage: $0 [--notes <text>] [--print-notes] <download URL for the signed app ZIP>" >&2
}

notes_arg=""
has_notes_arg=0
print_notes=0
address=""
has_address=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            notes_arg="$2"
            has_notes_arg=1
            shift 2
            ;;
        --notes=*)
            notes_arg="${1#*=}"
            has_notes_arg=1
            shift
            ;;
        --print-notes)
            print_notes=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                if [[ "$has_address" -eq 1 ]]; then
                    usage
                    exit 1
                fi
                address="$1"
                has_address=1
                shift
            done
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            if [[ "$has_address" -eq 1 ]]; then
                usage
                exit 1
            fi
            address="$1"
            has_address=1
            shift
            ;;
    esac
done

if [[ "$print_notes" -eq 1 && "$has_address" -eq 1 ]]; then
    usage
    exit 1
fi
if [[ "$print_notes" -eq 0 && "$has_address" -eq 0 ]]; then
    usage
    exit 1
fi

temp_key_file=""
cleanup() {
    if [[ -n "$temp_key_file" ]]; then
        rm -f "$temp_key_file"
    fi
}
trap cleanup EXIT

key_file="${SPARKLE_ED_KEY_FILE:-}"
if [[ -z "$key_file" && -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    cleaned_key="${SPARKLE_PRIVATE_KEY//$'\r'/}"
    cleaned_key="${cleaned_key#"${cleaned_key%%[![:space:]]*}"}"
    cleaned_key="${cleaned_key%"${cleaned_key##*[![:space:]]}"}"
    if [[ -n "$cleaned_key" ]]; then
        temp_key_file="$(mktemp "${TMPDIR:-/tmp}/vivebrush-ed-key.XXXXXX")"
        chmod 600 "$temp_key_file"
        printf '%s\n' "$cleaned_key" > "$temp_key_file"
        key_file="$temp_key_file"
    fi
fi

# Use the public GitHub release asset URL. Credentials must never be embedded.
python3 - "$address" "$print_notes" "$has_notes_arg" "$notes_arg" "$key_file" <<'PY'
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile


def extract_release_notes(notes_path: Path, version: str) -> str:
    if not notes_path.is_file():
        raise SystemExit(f'Missing {notes_path}.')
    heading = f'# ViveBrush {version}'
    heading_pattern = re.compile(rf'^#\s+ViveBrush\s+{re.escape(version)}$')
    in_section = False
    bullets: list[str] = []
    collecting_continuation = False
    for raw_line in notes_path.read_text(encoding='utf-8').splitlines():
        stripped = raw_line.strip()
        if not in_section:
            if heading_pattern.match(stripped):
                in_section = True
            continue
        if re.match(r'^#\s+', stripped):
            break
        lstrip = raw_line.lstrip()
        if lstrip.startswith(('- ', '* ')):
            bullet = lstrip[2:].strip()
            if bullet:
                bullets.append(bullet)
                collecting_continuation = True
            else:
                collecting_continuation = False
        elif collecting_continuation and raw_line[:1].isspace() and stripped:
            bullets[-1] = f'{bullets[-1]} {stripped}'
        else:
            collecting_continuation = False
    if not in_section:
        raise SystemExit(f"RELEASE_NOTES.md is missing section '{heading}'.")
    if not bullets:
        raise SystemExit(f"RELEASE_NOTES.md section '{heading}' has no release note bullets.")
    return ' '.join(bullets)


def resolve_description(version: str, has_notes_arg: bool, notes_arg: str) -> str:
    if has_notes_arg:
        text = notes_arg.strip()
        if not text:
            raise SystemExit('--notes must not be empty.')
        return text
    env_notes = os.environ.get('VIVEBRUSH_RELEASE_NOTES', '').strip()
    if env_notes:
        return env_notes
    return extract_release_notes(Path('RELEASE_NOTES.md'), version)


def verify_feed_signature(verifier: Path, public_key: str, feed_path: Path) -> None:
    data = feed_path.read_bytes()
    content, marker, block = data.rpartition(b'<!-- sparkle-signatures:\n')
    if not marker or b'-->' not in block:
        raise SystemExit('Signed appcast is missing embedded sparkle-signatures block.')
    fields = dict(line.split(':', 1) for line in block.split(b'-->', 1)[0].decode().splitlines() if ':' in line)
    if int(fields.get('length', '-1')) != len(content):
        raise SystemExit('Signed appcast length mismatch.')
    with tempfile.NamedTemporaryFile(prefix='vivebrush-feed-', suffix='.xml') as content_file:
        content_file.write(content)
        content_file.flush()
        subprocess.run([str(verifier), public_key, content_file.name, fields['edSignature'].strip()], check=True)


address = sys.argv[1]
print_notes = sys.argv[2] == '1'
has_notes_arg = sys.argv[3] == '1'
notes_arg = sys.argv[4]
key_file = sys.argv[5]

info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
description = resolve_description(version, has_notes_arg, notes_arg)
if print_notes:
    print(description)
    raise SystemExit(0)

url = urlsplit(address)
if not url.hostname or url.username is not None or url.password is not None or url.fragment or not (
    url.scheme == 'https' or (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost'))
):
    raise SystemExit('Use an HTTPS download URL without embedded credentials (or localhost for tests).')
if not info.get('SUPublicEDKey'):
    raise SystemExit('No update key is configured. On your personal Mac, run scripts/setup-update-key.sh --personal-mac first.')

directory = Path('dist') / version
archive = directory / f'ViveBrush-{version}-arm64.app.zip'
if not archive.is_file():
    raise SystemExit('No packaged app ZIP found. Run scripts/package.sh first.')
with zipfile.ZipFile(archive) as package:
    packaged_info = plistlib.loads(package.read('ViveBrush.app/Contents/Info.plist'))
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
    if packaged_info.get(key) != info.get(key):
        raise SystemExit(f'The packaged app has a different {key}. Run scripts/package.sh again before signing.')
if url.path.rsplit('/', 1)[-1] != archive.name:
    raise SystemExit(f'The download URL must end with {archive.name}.')
dmg = directory / f'ViveBrush-{version}-arm64.dmg'
if not dmg.is_file():
    raise SystemExit('No packaged DMG found. Run scripts/package.sh first.')
if key_file:
    key_path = Path(key_file)
    if not key_path.is_file() or key_path.stat().st_size == 0:
        raise SystemExit(f'Signing key file is missing or empty: {key_path}')

tools = Path('.build/artifacts/sparkle/Sparkle/bin')
sign_update = str(tools / 'sign_update')
account = 'com.vivebrush.app.updates'
public_key = info['SUPublicEDKey']
feed = directory / 'appcast.xml'

with tempfile.TemporaryDirectory(prefix='vivebrush-sign-') as temporary:
    verifier: Path | None = None
    if key_file:
        verifier = Path(temporary) / 'verify-signature'
        subprocess.run(['swiftc', 'scripts/verify-signature.swift', '-o', str(verifier)], check=True)
        signature = subprocess.check_output(
            [sign_update, '--ed-key-file', key_file, '-p', str(archive)], text=True
        ).strip()
        subprocess.run([str(verifier), public_key, str(archive), signature], check=True)
    else:
        keychain_public_key = subprocess.check_output(
            [str(tools / 'generate_keys'), '--account', account, '-p'], text=True
        ).strip()
        if keychain_public_key != public_key:
            raise SystemExit('The Keychain signing key does not match SUPublicEDKey. Import the original signing key first.')
        signature = subprocess.check_output(
            [sign_update, '--account', account, '-p', str(archive)], text=True
        ).strip()
        subprocess.run([sign_update, '--account', account, '--verify', str(archive), signature], check=True)

    sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    ET.register_namespace('sparkle', sparkle)
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'ViveBrush Updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'ViveBrush {version}'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    minimum = info['LSMinimumSystemVersion'].split('.')
    ET.SubElement(item, f'{{{sparkle}}}minimumSystemVersion').text = '.'.join(minimum + ['0'] * (3 - len(minimum)))
    ET.SubElement(item, f'{{{sparkle}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, f'{{{sparkle}}}version').text = info['CFBundleVersion']
    ET.SubElement(item, f'{{{sparkle}}}shortVersionString').text = version
    ET.SubElement(item, 'description').text = description
    ET.SubElement(item, 'enclosure', {
        'url': address,
        'length': str(archive.stat().st_size),
        'type': 'application/octet-stream',
        f'{{{sparkle}}}edSignature': signature,
    })
    ET.indent(root)
    ET.ElementTree(root).write(feed, encoding='utf-8', xml_declaration=True)

    try:
        if key_file:
            assert verifier is not None
            subprocess.run([sign_update, '--ed-key-file', key_file, str(feed)], check=True)
            verify_feed_signature(verifier, public_key, feed)
        else:
            subprocess.run([sign_update, '--account', account, str(feed)], check=True)
            subprocess.run([sign_update, '--account', account, '--verify', str(feed)], check=True)
    except BaseException:
        feed.unlink(missing_ok=True)
        raise

files = [dmg, archive, feed]
(directory / 'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in files))
print(f'Signed update feed: {feed}')
PY
