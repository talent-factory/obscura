# Obscura — task runner (headless browser engine in Rust)
#
# Prereqs:
#   just ≥ 1.18 (brew install just)   ·   Rust toolchain (rustup)   ·   cargo-nextest
#   cmake (only for the `stealth` builds)   ·   the first build compiles V8 (~5 minutes)
#
# List all recipes by group:   `just`
# Single group:                `just --list | grep -A99 '\[Quality\]'`

set dotenv-load            # loads .env into the recipe environment (if present)
set shell := ["bash", "-uc"]
set positional-arguments

# Build settings from AGENTS.md: no incremental build, two jobs (V8 is heavy).
export CARGO_INCREMENTAL := "0"
export CARGO_BUILD_JOBS := "2"

# Path of the release binary, used by the obstacle course and the render harness.
bin := justfile_directory() / "target/release/obscura"

# Path of the companion repo with the obstacle course (33 stages, must stay 33/33).
benchmark_dir := env("OBSCURA_BENCHMARK_DIR", justfile_directory() / "../obscura-benchmark")

# The version of the workspace, from `Cargo.toml`.
version := `sed -n '/^\[workspace.package\]/,/^\[/{s/^version = "\(.*\)"/\1/p;}' Cargo.toml`

# Default: grouped recipe list (file order preserved).
default:
    @just --list --unsorted

# ─────────────────────────── Development ───────────────────────────────────

# Build the release binaries with rendering (the build that AGENTS.md requires).
[group('Development')]
build:
    cargo build --release -p obscura-cli --bins --features render

# Build the release binaries with rendering and stealth (needs cmake).
[group('Development')]
build-stealth:
    cargo build --release -p obscura-cli --bins --features render,stealth

# Build the release binaries without rendering (rustls only).
[group('Development')]
build-minimal:
    cargo build --release -p obscura-cli --bins --no-default-features

# Build the release binaries without rendering, with stealth.
[group('Development')]
build-minimal-stealth:
    cargo build --release -p obscura-cli --bins --no-default-features --features stealth

# Fast debug build of the CLI only (does not relink the whole workspace).
[group('Development')]
build-dev:
    cargo build -p obscura-cli

# Run the CLI.  Usage:  just run fetch https://example.com --dump text
[group('Development')]
run *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$#" -eq 0 ]; then set -- --help; fi
    cargo run --release -p obscura-cli --features render -- "$@"

# Fetch a page.  Usage:  just fetch https://example.com [text|html|links|markdown|...]
[group('Development')]
fetch url dump="text":
    {{bin}} fetch "{{url}}" --dump "{{dump}}"

# Start the CDP server for Puppeteer/Playwright (default port 9222).
[group('Development')]
serve port="9222":
    {{bin}} serve --port {{port}}

# Fast type check without code generation.
[group('Development')]
check:
    cargo check --workspace --all-targets --features render

# ─────────────────────────── Quality ──────────────────────────────────────

# Run tests of one crate, or of all crates (nextest: one V8 isolate per process).
[group('Quality')]
test crate="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{crate}}" ]; then
        cargo nextest run --release --features render -p "{{crate}}"
    else
        cargo nextest run --release --features render --no-fail-fast
    fi

# Run the linter (clippy).
[group('Quality')]
lint:
    cargo clippy --workspace --all-targets --features render

# Check one file with rustfmt (no format-all recipe: the tree is not rustfmt-clean).
[group('Quality')]
format-check file:
    rustfmt --edition 2021 --check "{{file}}"

# Check licenses, bans, advisories, sources (`deny.toml`; needs cargo-deny).
[group('Quality')]
deps:
    cargo deny check

# Behavioral gate: the obstacle course of the companion repo (must report 33/33).
[group('Quality')]
obstacle-course: build
    cd "{{benchmark_dir}}" && OBSCURA_BIN="{{bin}}" python3 obstacle-course/run.py --runs 1 --warmup 0

# Everything AGENTS.md asks for before finishing: build, tests, obstacle course.
[group('Quality')]
ci: build test obstacle-course

# ─────────────────────────── Rendering ────────────────────────────────────

# Run the deterministic render fixtures into a disposable directory outside the repo.
[group('Rendering')]
render-fixtures: build
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(mktemp -d)"
    OBSCURA_BIN="{{bin}}" render-repros/run.sh "$root/fixtures"
    echo "output: $root/fixtures"

# Run the representative real-site suite (top or bottom of the page) into a disposable directory.
[group('Rendering')]
render-suite position="top": build
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(mktemp -d)"
    if [ "{{position}}" = "bottom" ]; then
        OBSCURA_BIN="{{bin}}" render-repros/representative-suite/run.sh "$root/bottom" bottom
    else
        OBSCURA_BIN="{{bin}}" render-repros/representative-suite/run.sh "$root/top"
    fi
    echo "output: $root"

# ─────────────────────────── Misc ─────────────────────────────────────

# Show the workspace version.
[group('Misc')]
version:
    @echo "obscura {{version}}"

# Clean build artifacts (the next build compiles V8 again, ~5 minutes).
[group('Misc')]
clean:
    cargo clean
