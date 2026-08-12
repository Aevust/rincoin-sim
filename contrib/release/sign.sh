#!/usr/bin/env bash
# contrib/release/sign.sh  (rincoin-sim)
#
# Generate SHA256SUMS over the rincoin-sim release artifacts in a directory and
# produce a DETACHED, armored GPG signature (SHA256SUMS.asc) with a single key.
#
# rincoin-sim is a single-maintainer personal repository, so exactly one signer
# is expected. The script RE-HASHES whatever rincoin-sim-*.tar.gz are actually
# present, so the manifest matches the distributed bytes with no transit /
# line-ending ambiguity, then signs SHA256SUMS and verifies the result.
#
# Usage:
#   bash sign.sh <artifacts-dir> [KEY]
#
# Examples:
#   bash sign.sh ./release-artifacts                          # default key
#   bash sign.sh ./release-artifacts 0ED99C46B2192E375381EF4AC5BEF8A9FA06C16F

set -euo pipefail

DIR="${1:-.}"
# Signer: Aevust ed25519 (personal rincoin-sim repo). Override by passing the key
# fingerprint as the second argument.
KEY="${2:-0ED99C46B2192E375381EF4AC5BEF8A9FA06C16F}"

cd "$DIR"

# sha256 tool: coreutils sha256sum on Linux and Git Bash; shasum fallback.
if command -v sha256sum >/dev/null 2>&1; then
    HASH() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
    HASH() { shasum -a 256 "$@"; }
else
    echo "error: neither sha256sum nor shasum found on PATH" >&2
    exit 1
fi

MANIFEST=SHA256SUMS
SIG=SHA256SUMS.asc

# Collect artifacts (bash pathname expansion is already sorted). rincoin-sim is
# Linux-only, so only tarballs — this also matches `make dist`'s source tarball.
shopt -s nullglob
FILES=( rincoin-sim-*.tar.gz )
if (( ${#FILES[@]} == 0 )); then
    echo "error: no rincoin-sim-*.tar.gz artifacts found in $(pwd)" >&2
    exit 1
fi

echo "==> hashing ${#FILES[@]} artifact(s) in $(pwd)"
HASH "${FILES[@]}" > "$MANIFEST"   # LF newlines
echo "==> $MANIFEST"
cat "$MANIFEST"
echo

echo "==> detached-signing $MANIFEST with key $KEY"
rm -f "$SIG"
gpg --local-user "$KEY" --detach-sign --armor --output "$SIG" "$MANIFEST"

echo "==> verifying $SIG"
gpg --verify "$SIG" "$MANIFEST"

echo
echo "==> OK"
echo "    $(pwd)/$MANIFEST       <- publish (the file 'sha256sum -c' checks against)"
echo "    $(pwd)/$SIG   <- publish (detached, armored signature)"
