# List available recipes
default:
    @just --list

# Build all Swift targets in debug mode
build:
    swift build

# Build all Swift targets in release mode
build-release:
    swift build -c release

# Run all Swift unit and integration tests
test:
    swift test

# Lint, verify, and generate Swift OmniBuf code from proto/ using protoc-gen-omnibuf-swift
proto:
    buf lint
    swift build -c release --product protoc-gen-omnibuf-swift
    buf generate

# Alias for proto code generation
generate: proto

# Run the cross-language OmniBuf conformance suite across all 4 tiers
conformance:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release --product conformance-swift
    if [[ -n "${CONFORMANCE_RUNNER:-}" ]]; then
        RUNNER="$CONFORMANCE_RUNNER"
    elif [[ -x "../omnibuf-go/bin/conformance-runner" ]]; then
        RUNNER="../omnibuf-go/bin/conformance-runner"
    elif command -v conformance-runner >/dev/null 2>&1; then
        RUNNER="conformance-runner"
    elif command -v go >/dev/null 2>&1; then
        exec go run github.com/omnibuf/omnibuf-go/cmd/conformance-runner@71dad83aadd7dc65401d662521d34cfaeb1011ab ./.build/release/conformance-swift
    else
        echo "conformance-runner binary not found; set CONFORMANCE_RUNNER or install conformance-runner" >&2
        exit 1
    fi
    "$RUNNER" ./.build/release/conformance-swift

# Run the PeerUpdate benchmark suite and write testdata/benchmarks.json
bench:
    swift run -c release OmniBufBench

# Lint Swift sources and Protobuf schemas
lint:
    if command -v swiftlint >/dev/null 2>&1; then swiftlint lint --strict; fi
    if command -v buf >/dev/null 2>&1; then buf lint; fi

# Format Swift and Protobuf files in place
fmt:
    if command -v swift-format >/dev/null 2>&1; then swift-format format --in-place --recursive Sources Tests Package.swift; fi
    if command -v buf >/dev/null 2>&1; then buf format -w; fi

# Check Swift and Protobuf formatting without modifying files
fmt-check:
    if command -v swift-format >/dev/null 2>&1; then swift-format lint --recursive Sources Tests Package.swift; fi
    if command -v buf >/dev/null 2>&1; then buf format -d --exit-code; fi

# Run the complete CI verification pipeline
ci: fmt-check lint build test conformance
