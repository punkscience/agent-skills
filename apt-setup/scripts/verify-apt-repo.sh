#!/usr/bin/env bash
# verify-apt-repo.sh — End-to-end verification of an APT repo WITHOUT root and
# WITHOUT touching the system's apt state.
#
# How it works: it relocates apt's *entire* Dir tree into a throwaway root and
# sets APT::Sandbox::User to the current user (so the _apt download sandbox does
# not block writes into our temp dir). This lets `apt-get update` run as a normal
# user against any repo URL — proving exactly what a real user's `sudo apt update`
# would see, including the apt 3.x "weak security information" gate.
#
# Usage:
#   verify-apt-repo.sh <repo-url> <keyring> <pkg-name> [suite] [component]
#
#   <repo-url>   e.g. https://punkscience.github.io/derpy/apt
#   <keyring>    path to a binary GPG keyring file, OR a URL to download one
#   <pkg-name>   the package that should become installable, e.g. derpy
#   [suite]      default: stable
#   [component]  default: main
#
# Exit 0 only if: signature verifies, strong hashes bind, and <pkg-name>
# resolves to an install candidate. Anything else exits non-zero.
set -euo pipefail

REPO_URL="${1:?repo-url required}"
KEYRING_IN="${2:?keyring path or URL required}"
PKG="${3:?package name required}"
SUITE="${4:-stable}"
COMPONENT="${5:-main}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aptverify.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Resolve keyring: download if it looks like a URL.
KEYRING="$WORK/keyring.gpg"
case "$KEYRING_IN" in
  http://*|https://*) curl -fsSL "$KEYRING_IN" -o "$KEYRING" ;;
  *) cp "$KEYRING_IN" "$KEYRING" ;;
esac

# Sanity: keyring must be BINARY (not ASCII-armored). signed-by wants binary.
if head -c 40 "$KEYRING" | grep -q "BEGIN PGP PUBLIC KEY BLOCK"; then
  echo "FAIL: keyring is ASCII-armored. Serve a binary keyring (gpg --export > file)," >&2
  echo "      not armored (gpg --armor --export)." >&2
  exit 3
fi

D="$WORK/root"
mkdir -p "$D/etc/apt/sources.list.d" "$D/etc/apt/apt.conf.d" "$D/etc/apt/preferences.d" \
         "$D/var/lib/apt/lists/partial" "$D/var/lib/dpkg" "$D/var/cache/apt/archives/partial"
: > "$D/var/lib/dpkg/status"

printf 'deb [signed-by=%s] %s %s %s\n' "$KEYRING" "$REPO_URL" "$SUITE" "$COMPONENT" \
  > "$D/etc/apt/sources.list"

{
  printf 'Dir "%s";\n' "$D"
  printf 'Dir::State::status "%s/var/lib/dpkg/status";\n' "$D"
  printf 'APT::Sandbox::User "%s";\n' "$(id -un)"
} > "$D/apt.conf"

echo "==> apt-get update against $REPO_URL ($SUITE/$COMPONENT)"
if ! APT_CONFIG="$D/apt.conf" apt-get update 2>&1 | sed 's/^/    /'; then
  echo "FAIL: apt-get update returned non-zero." >&2
  exit 1
fi

# A successful update can still emit the killer warning while exiting 0 under
# some configs — re-run and grep so we never report a false pass.
OUT="$(APT_CONFIG="$D/apt.conf" apt-get update 2>&1 || true)"
if grep -qiE 'No Hash entry|weak security information|not signed|NO_PUBKEY|following signatures' <<<"$OUT"; then
  echo "FAIL: apt reported a security/hash problem:" >&2
  grep -iE 'No Hash entry|weak security|not signed|NO_PUBKEY|following signatures' <<<"$OUT" | sed 's/^/    /' >&2
  exit 1
fi

echo "==> resolving package: $PKG"
POLICY="$(APT_CONFIG="$D/apt.conf" apt-cache policy "$PKG" 2>&1 || true)"
echo "$POLICY" | sed 's/^/    /'
if ! grep -q "Candidate:" <<<"$POLICY" || grep -q "Candidate: (none)" <<<"$POLICY"; then
  echo "FAIL: $PKG has no install candidate from this repo." >&2
  exit 2
fi

echo "PASS: repo is signed, strong-hashed, and '$PKG' is installable."
