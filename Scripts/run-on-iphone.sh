#!/usr/bin/env bash
# Builds one of Parhelion's examples for iOS with Apple's SwiftUI, installs it on the iPhone
# connected by USB, and starts it:
#
#     Scripts/run-on-iphone.sh Tasks
#
# Needs xtool with the iOS SDK and a signed-in team (`xtool setup`), and the iPhone unlocked,
# trusted, and in Developer Mode. Starting the app also needs pymobiledevice3 and its tunnel
# (`sudo pymobiledevice3 remote tunneld`); without them the app is installed and you tap it.
set -euo pipefail

name="${1:?usage: Scripts/run-on-iphone.sh EXAMPLE, for example Tasks}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$repo/Examples/$name"
if [[ ! -d "$source_dir" ]]; then
    echo "No example named $name. Choose one of: $(ls "$repo/Examples" | tr '\n' ' ')" >&2
    exit 2
fi

# An xtool app is a package whose library's @main type is the app. The work folder is kept
# between runs, so a second run builds only what changed.
work="${XDG_CACHE_HOME:-$HOME/.cache}/parhelion/iphone/$name"
mkdir -p "$work"
rm -rf "$work/Sources"
mkdir -p "$work/Sources/$name"
cp -R "$source_dir"/. "$work/Sources/$name/"
cat > "$work/Package.swift" <<MANIFEST
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "$name",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "$name", targets: ["$name"])],
    targets: [.target(name: "$name")]
)
MANIFEST
printf 'version: 1\nbundleID: dev.parhelion.%s\n' "$name" > "$work/xtool.yml"

(cd "$work" && xtool dev run)

# xtool installs the app; start it if pymobiledevice3 can reach the phone. xtool prefixes the
# bundle identifier with the team, so look it up.
if command -v pymobiledevice3 > /dev/null; then
    bundle="$(pymobiledevice3 apps list 2> /dev/null | python3 -c '
import json, sys
suffix = "dev.parhelion." + sys.argv[1]
ids = [k for k in json.load(sys.stdin) if k == suffix or k.endswith("." + suffix)]
print(ids[0] if ids else "")' "$name" || true)"
    if [[ -n "$bundle" ]] && pymobiledevice3 developer dvt launch --tunnel "" "$bundle" > /dev/null 2>&1; then
        echo "Started $name on the iPhone."
        exit 0
    fi
fi
echo "Installed $name. Tap it on the iPhone to open it."
