#!/bin/bash
set -euo pipefail

# Deliberately opt in on a personal Mac. Builds and tests never call this script.
if [[ $# -ne 1 || "${1:-}" != "--personal-mac" ]]; then
    echo "Run only on your personal Mac: $0 --personal-mac" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift package resolve
tool="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
account="com.vivebrush.app.updates"
configured_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"

if [[ -z "$configured_key" ]]; then
    "$tool" --account "$account"
fi
public_key="$("$tool" --account "$account" -p)"
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Could not read a valid update-signing public key from this Mac." >&2
    exit 1
fi
if [[ -n "$configured_key" && "$configured_key" != "$public_key" ]]; then
    echo "The existing public key does not match this Mac. An established update key must not be replaced automatically." >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $public_key" Resources/Info.plist
echo "Configured the public key in Resources/Info.plist. The private key stays in this Mac's Keychain."
