#!/usr/bin/env bash
# gen-gpg-key.sh — Generate a non-interactive APT signing key and emit both the
# private key (for the CI secret) and the binary public keyring (for gh-pages).
#
# Usage:
#   gen-gpg-key.sh "<Name-Real>" "<email>" <out-dir>
# Example:
#   gen-gpg-key.sh "derpy Packaging" derpy-packaging@punkscience.ca ./_aptkeys
#
# Produces, in <out-dir>:
#   private-key.asc            -> upload as the APT_SIGNING_KEY repo secret
#   <keyring>-archive-keyring.gpg (binary) -> commit to gh-pages apt/ root
#
# The key has NO passphrase (%no-protection) because CI must use it unattended.
# Treat private-key.asc as a secret: it is uploaded to GitHub Actions secrets and
# should NOT be committed. This script does not delete it; the caller should.
set -euo pipefail

NAME="${1:?Name-Real required}"
EMAIL="${2:?email required}"
OUTDIR="${3:?output dir required}"
mkdir -p "$OUTDIR"

# Use an ephemeral GNUPGHOME so we never touch the user's real keyring.
GNUPGHOME="$(mktemp -d "${TMPDIR:-/tmp}/aptgpg.XXXXXX")"
export GNUPGHOME
chmod 700 "$GNUPGHOME"
cleanup() { rm -rf "$GNUPGHOME"; }
trap cleanup EXIT

gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: ${NAME}
Name-Email: ${EMAIL}
Expire-Date: 0
%no-protection
%commit
EOF

gpg --batch --yes --armor --export-secret-keys "$EMAIL" > "$OUTDIR/private-key.asc"
gpg --batch --yes --export "$EMAIL" > "$OUTDIR/keyring.gpg"   # BINARY (no --armor)

echo "Wrote:"
echo "  $OUTDIR/private-key.asc   (private — upload as APT_SIGNING_KEY secret, then delete)"
echo "  $OUTDIR/keyring.gpg       (binary public keyring — serve on gh-pages)"
echo
echo "Fingerprint:"
gpg --batch --fingerprint "$EMAIL" | sed 's/^/  /'
