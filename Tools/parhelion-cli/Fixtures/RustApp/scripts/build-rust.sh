#!/bin/sh
# Builds the Rust library and generates its Swift bindings with UniFFI.
# `parhelion run` runs it before `swift build`; see parhelion.json.
#
# It writes a generated file only when its content changed, because the
# watcher treats a write to a Swift file as an edit and would rebuild again.
set -eu

cd "$(dirname "$0")/.."
profile="${PARHELION_CONFIGURATION:-debug}"
flags=""
if [ "$profile" = release ]; then flags="--release"; fi

# shellcheck disable=SC2086
cargo build $flags --quiet
library="target/$profile/libfixture_backend.so"

# Not under the package: the watcher would see the Swift file in it.
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
# shellcheck disable=SC2086
cargo run $flags --quiet --bin uniffi-bindgen -- generate \
    --library "$library" --language swift --no-format --out-dir "$out"

install_if_changed() {
    mkdir -p "$(dirname "$2")"
    if ! cmp -s "$1" "$2"; then cp "$1" "$2"; fi
}

# swift-format must not lint generated code.
{ echo "// swift-format-ignore-file"; cat "$out/fixture_backend.swift"; } > "$out/Generated.swift"
install_if_changed "$out/Generated.swift" Sources/RustApp/Generated/fixture_backend.swift
install_if_changed "$out/fixture_backendFFI.h" \
    Sources/fixture_backendFFI/include/fixture_backendFFI.h
