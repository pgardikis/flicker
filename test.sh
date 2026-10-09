#!/bin/bash
# Builds and runs the warning rule tests. No Xcode needed, like build.sh.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p build
swiftc -parse-as-library -swift-version 6 Sources/WarningRules.swift Tests/*.swift -o build/tests
build/tests
