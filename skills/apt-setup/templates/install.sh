#!/usr/bin/env bash
# __PKG__ one-liner installer.
#
#   curl -fsSL https://__OWNER__.github.io/__REPO__/install.sh | bash
#
# Placeholders: __PKG__ __OWNER__ __REPO__ __KEYRING__
set -euo pipefail

GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

if [ "$(uname -s)" != "Linux" ]; then
  echo "This installer is for Debian/Ubuntu (APT). On other platforms install __PKG__ another way." >&2
  exit 1
fi

# Require root for package operations. Re-exec via sudo if needed. When piped
# (curl|bash or bash <(curl)), $0 is /dev/fd/N which sudo cannot read, so
# re-fetch the script from its canonical URL before elevating.
if [ "$(id -u)" -ne 0 ] && [ -z "${SUDO_USER:-}" ]; then
  echo -e "${BOLD}📦 __PKG__ installer — Linux (APT)${NC}"
  echo "  Adds the __PKG__ APT repo + signing key, then installs __PKG__ (needs root)."
  if [ ! -f "$0" ] || [ "${0#/dev/fd/}" != "$0" ]; then
    TMP="$(mktemp)"
    curl -fsSL "https://__OWNER__.github.io/__REPO__/install.sh" -o "$TMP"
    exec sudo bash "$TMP"
  fi
  exec sudo bash "$0"
fi

echo "  → Installing signing key…"
curl -fsSL "https://__OWNER__.github.io/__REPO__/apt/__KEYRING__" \
  -o /usr/share/keyrings/__KEYRING__

echo "  → Adding APT source…"
cat > /etc/apt/sources.list.d/__PKG__.list <<SOURCELIST
deb [signed-by=/usr/share/keyrings/__KEYRING__] https://__OWNER__.github.io/__REPO__/apt/ stable main
SOURCELIST

echo "  → Updating package lists…"
apt-get update -qq

echo "  → Installing __PKG__…"
apt-get install -y __PKG__

echo -e "${GREEN}✓ __PKG__ installed. Run: __PKG__ --help${NC}"
