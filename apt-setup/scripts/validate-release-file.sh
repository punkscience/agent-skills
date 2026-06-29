#!/usr/bin/env bash
# validate-release-file.sh — Static linter for a Debian `Release` / `InRelease`
# file. Catches the #1 cause of "No Hash entry in Release file" /
# "provides only weak security information" on apt 3.x: a blank line that breaks
# the single control-file stanza, detaching the checksum fields from the Release
# paragraph.
#
# Usage:
#   validate-release-file.sh <path-or-url>
#
# Pass a local Release/InRelease file, or a URL (it will be downloaded).
# Exit 0 if the file is well-formed; non-zero with diagnostics otherwise.
set -euo pipefail

SRC="${1:?path or URL to Release/InRelease required}"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
case "$SRC" in
  http://*|https://*) curl -fsSL "${SRC}?cb=$$" -o "$TMP" ;;  # cache-bust CDN
  *) cp "$SRC" "$TMP" ;;
esac

# Extract the metadata body. For a clearsigned InRelease, the body is between the
# PGP header (after its blank line) and the signature. For a plain Release the
# whole file is the body.
BODY="$(mktemp)"; trap 'rm -f "$TMP" "$BODY"' EXIT
if grep -q "BEGIN PGP SIGNED MESSAGE" "$TMP"; then
  # Drop everything up to and including the first blank line (PGP armor headers),
  # and stop at the signature block.
  awk 'BEGIN{inhdr=1} /BEGIN PGP SIGNATURE/{exit}
       inhdr && /^$/ {inhdr=0; next}
       !inhdr {print}' "$TMP" > "$BODY"
else
  cat "$TMP" > "$BODY"
fi

fail=0
note() { echo "  - $*"; }

# 1) THE stanza bug: any blank line inside the body splits the stanza.
if grep -qE '^$' "$BODY"; then
  echo "FAIL: blank line(s) inside the Release stanza (breaks the control-file paragraph)."
  note "A Release file is ONE stanza. The MD5Sum/SHA1/SHA256/SHA512 checksums are"
  note "fields of that stanza — there must be NO blank line between 'Date:' and the"
  note "first checksum header, nor between checksum sections."
  note "Offending line numbers (within body):"
  grep -nE '^$' "$BODY" | sed 's/^/      /'
  fail=1
fi

# 2) Strong hashes must be present (apt 3.x rejects MD5Sum/SHA1-only as weak).
have_strong=0
grep -qE '^SHA256:' "$BODY" && have_strong=1
grep -qE '^SHA512:' "$BODY" && have_strong=1
if [ "$have_strong" -eq 0 ]; then
  echo "FAIL: no SHA256 or SHA512 section. apt 3.x treats MD5Sum/SHA1 as weak."
  fail=1
fi

# 3) Required fields present.
for f in Origin Suite Components Architectures Date; do
  grep -qE "^${f}:" "$BODY" || { echo "FAIL: missing required field '${f}:'"; fail=1; }
done

# 4) Each checksum line must have 3 fields (hash size path). Multiple spaces ok.
badlines="$(awk '
  /^(MD5Sum|SHA1|SHA256|SHA512):/ {sec=1; next}
  /^[^ ]/ {sec=0}
  sec && NF>0 && NF!=3 {print NR": "$0}
' "$BODY" || true)"
if [ -n "$badlines" ]; then
  echo "FAIL: malformed checksum line(s) (expected 'hash size path'):"
  echo "$badlines" | sed 's/^/      /'
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: Release stanza is well-formed (single paragraph, strong hashes present)."
fi
exit "$fail"
