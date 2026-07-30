---
name: apt-setup
description: Set up a code repository end-to-end for APT (Debian/Ubuntu) distribution — produce .deb packages, publish a GPG-signed APT repository on GitHub Pages, and a one-line installer — with full automated verification. Use when the user wants to distribute their app via apt, "apt install", a Debian/Ubuntu package, an APT repo, a .deb, or a `curl | bash` Linux installer.
---

# APT Distribution Setup

Take a repository from "builds a binary" to "users run `sudo apt install <pkg>`",
doing as much as possible automatically. The goal is **zero manual steps** for the
user where the tooling allows it (`gh` uploads the signing-key secret, enables
Pages, triggers the workflow; the skill generates the key and verifies the live
repo). Where a step genuinely requires a human (rare), make it one copy-paste.

Work on a dedicated branch and offer to merge at the end.

## Operating principles

- **Verify, don't assume.** Never tell the user "it works" until
  `scripts/verify-apt-repo.sh` passes against the *live* repo. We confirm what a
  real `sudo apt update` sees.
- **Minimize intervention.** Prefer `gh` automation over hand instructions. Only
  fall back to manual when a capability is missing (e.g. no `gh` auth, no `gpg`).
- **Surgical.** Add packaging/CI files; don't refactor the project.
- Run all shell/apt steps in a **Linux** environment. On Windows, use WSL
  (`wsl.exe -- bash -lc '…'`); for non-trivial scripts, base64-encode the script
  and `echo <b64> | base64 -d | bash` to avoid quoting corruption.

---

## Phase 0 — Preflight: can this repo build a Linux binary?

This is the gate. APT ships Linux binaries; if the project can't produce one,
nothing downstream matters.

1. Detect language/build system: `go.mod` (Go), `Cargo.toml` (Rust),
   `package.json` (Node), `pyproject.toml`/`setup.py` (Python),
   `CMakeLists.txt`/`Makefile` (C/C++), or a prebuilt-binary repo.
2. Determine whether a **Linux amd64** (and ideally **arm64**) binary is
   produced today:
   - Go: try `GOOS=linux GOARCH=amd64 go build ./...`. Note CGO — if `CGO_ENABLED`
     must be 1, cross-compiling needs a C toolchain; flag it.
   - Rust: `cargo build --release` (+ `rustup target add` for cross).
   - Others: look for an existing build target/CI that emits a Linux binary.
   - Check `.github/workflows/*` for an existing release/build pipeline.
3. **If it does NOT build on Linux:** stop and offer to set that up first. Use
   `AskUserQuestion` to confirm scope. For Go this is usually trivial (it already
   cross-compiles); for compiled-with-CGO or other languages, set up the minimal
   Linux build and confirm `file <binary>` reports an ELF binary before moving on.
   Do not proceed to packaging until a Linux binary exists.

State what you found (language, arches, whether Linux build works) before continuing.

---

## Phase 1 — Branch

1. Infer the branch naming convention: inspect `git branch -a`, recent merge
   commits, and any `CONTRIBUTING`/`docs`. Common patterns: `feature/<x>`,
   `feat/<x>`, `<user>/<x>`.
2. Create and switch: default `feature/apt-setup` (adapt to the detected pattern).
3. If the working tree is dirty, note it; branch from the current HEAD.

---

## Phase 1.5 — License (UNLICENSE by default)

apt packaging records an SPDX license (the nfpms `license:` field, and the
package's copyright). Make it consistent with what the repo actually carries.

1. If the repo already has a `LICENSE`/`LICENSE.txt`/`COPYING`, use it; reuse its
   SPDX identifier in the nfpms `license:` field.
2. **If no license file exists, add UNLICENSE** (public domain) — copy
   `templates/UNLICENSE` → repo-root `LICENSE`, and set the nfpms `license:` field
   to `Unlicense` (the SPDX id). Do not ask; this is the default. Mention it so the
   user can override.

---

## Phase 2 — Produce `.deb` packages

The `.deb` filenames **must** match what the publisher downloads:
`<pkg>_<version>_<arch>.deb` (e.g. `derpy_1.0.1_amd64.deb`).

Pick the path that fits the project:

- **Go + goreleaser already present** (`.goreleaser.y*ml`): add an `nfpms:` block
  if missing. Minimal form:
  ```yaml
  nfpms:
    - id: <pkg>
      package_name: <pkg>
      file_name_template: "{{ .PackageName }}_{{ .Version }}_{{ .Arch }}"
      vendor: <vendor>
      maintainer: <name> <email>
      homepage: <url>
      description: <one-line>
      license: <spdx>   # default Unlicense if the repo has no license file (Phase 1.5)
      formats: [deb]
      section: <e.g. sound/utils>
      priority: optional
  ```
  Ensure the release workflow runs goreleaser on tag push (see derpy's
  `.github/workflows/release.yml` as a reference shape).
- **Go without goreleaser:** add goreleaser (recommended) or use `templates/nfpm.yaml`.
- **Rust:** `cargo install cargo-deb`; `cargo deb`. Rename output to the required
  filename pattern, or set it via `cargo-deb` config.
- **Anything else:** `templates/nfpm.yaml` (build Linux binaries, then `nfpm package`),
  or `fpm`, or a hand-rolled `dpkg-deb --build`.

Whatever the route, the **release CI must upload the `.deb` files as release
assets** for each arch, because the publisher pulls them with `gh release download`.

Confirm: after a (test) release, `gh release view <tag> --json assets` lists
`<pkg>_<version>_<arch>.deb` for every arch.

---

## Phase 3 — Signing key (automated)

apt requires a signed repo. Check first whether it's already set up:
`gh secret list` for `APT_SIGNING_KEY`, and whether a keyring is already served.

If not:

1. Generate the key (no passphrase — CI is unattended):
   ```bash
   bash scripts/gen-gpg-key.sh "<pkg> Packaging" <packaging-email> ./_aptkeys
   ```
   Derive name/email from `git config user.*` or ask. This writes
   `_aptkeys/private-key.asc` and the **binary** `_aptkeys/keyring.gpg`.
2. Upload the private key as the CI secret (no manual GitHub UI step):
   ```bash
   gh secret set APT_SIGNING_KEY < _aptkeys/private-key.asc
   ```
3. The public **binary** keyring will be committed to gh-pages as
   `apt/<pkg>-archive-keyring.gpg` in Phase 4 / by the publisher workflow.
4. **Delete the private key locally** and never commit it:
   `rm -f _aptkeys/private-key.asc`. Add `_aptkeys/` to `.gitignore`.

If `gh` lacks permission to set secrets, fall back to a single instruction:
"paste the contents of `_aptkeys/private-key.asc` into Settings → Secrets →
Actions → New secret named `APT_SIGNING_KEY`."

---

## Phase 4 — gh-pages + GitHub Pages (automated)

1. If no `gh-pages` branch exists, create an orphan one with a placeholder, and
   seed the keyring:
   ```bash
   git switch --orphan gh-pages
   git rm -rf . 2>/dev/null || true
   mkdir -p apt
   cp _aptkeys/keyring.gpg apt/<pkg>-archive-keyring.gpg   # binary keyring
   echo "<pkg> apt repo" > index.html
   git add apt index.html && git commit -m "chore: seed gh-pages apt repo"
   git push -u origin gh-pages
   git switch -   # back to the feature branch
   ```
2. Enable Pages from the `gh-pages` branch root (no UI):
   ```bash
   gh api -X POST repos/{owner}/{repo}/pages \
     -f 'source[branch]=gh-pages' -f 'source[path]=/' 2>/dev/null \
   || gh api -X PUT repos/{owner}/{repo}/pages \
     -f 'source[branch]=gh-pages' -f 'source[path]=/'
   ```
   (POST to create, PUT to update if already enabled.)

---

## Phase 5 — Install the publisher workflow + installer

1. Copy `templates/apt-repo.yml` → `.github/workflows/apt-repo.yml` and replace
   placeholders: `__OWNER__ __REPO__ __PKG__ __ORIGIN__ __LABEL__ __DESC__
   __KEYRING__ __ARCHES__`.
2. Copy `templates/install.sh` → repo root `install.sh`; replace
   `__PKG__ __OWNER__ __REPO__ __KEYRING__`; `chmod +x install.sh`.
3. Commit these on the feature branch.

> The publisher workflow generates a **single-stanza** Release file on purpose —
> see "Critical knowledge" below. Do not reintroduce blank lines before the
> checksum sections.

---

## Phase 6 — Build the repo for the first time

The publisher needs a release whose assets include the `.deb` files.

- If a suitable release already exists (assets present), use its tag.
- Otherwise cut one: bump version, `git tag vX.Y.Z && git push origin vX.Y.Z`,
  let the release workflow build and upload the `.deb` assets. Confirm with
  `gh release view <tag> --json assets`.

> **`workflow_dispatch` runs the workflow definition from the DEFAULT branch.**
> If `apt-repo.yml` is only on the feature branch, either merge first (Phase 8)
> or, for an isolated test, push the workflow to the default branch. Plan the
> order with the user; usually: merge, then dispatch.

Trigger and wait:
```bash
gh workflow run "APT Repository" -f tag=<tag>
gh run watch <run-id> --exit-status
```

---

## Phase 7 — Verify (hard gates — all must pass)

Run from a Linux env. CDN (GitHub Pages/Fastly) can lag a minute; cache-bust
structural fetches and retry the apt check if needed.

1. **Release stanza is well-formed** (catches the #1 failure offline):
   ```bash
   bash scripts/validate-release-file.sh \
     https://<owner>.github.io/<repo>/apt/dists/stable/InRelease
   ```
2. **Signature verifies** against the served keyring:
   ```bash
   curl -fsSL https://<owner>.github.io/<repo>/apt/<pkg>-archive-keyring.gpg -o /tmp/k.gpg
   file /tmp/k.gpg            # must say "OpenPGP Public Key", NOT armored block
   curl -fsSL https://<owner>.github.io/<repo>/apt/dists/stable/InRelease -o /tmp/ir
   gpgv --keyring /tmp/k.gpg /tmp/ir
   ```
3. **End-to-end apt install path** (no root, no system impact):
   ```bash
   bash scripts/verify-apt-repo.sh \
     https://<owner>.github.io/<repo>/apt \
     https://<owner>.github.io/<repo>/apt/<pkg>-archive-keyring.gpg \
     <pkg> stable main
   ```
   This must print `PASS:` — meaning `apt-get update` succeeded with no weak/hash
   warning and `<pkg>` resolved to an install candidate.

Only after all three pass, report success and give the user the install one-liner.

---

## Phase 8 — Merge

1. Summarize what changed (files added, key/secret created, Pages enabled, verify
   results).
2. Offer to merge `feature/apt-setup` → default branch, matching the user's
   workflow (open a PR with `gh pr create`, or fast-forward merge if they prefer).
   Remember: the publisher workflow becomes dispatchable from the default branch
   only after merge — re-dispatch + re-verify if the first publish ran from a
   branch/test push.

---

## Critical knowledge (the gotchas that cost real debugging time)

- **The Release file is ONE Debian control stanza.** The `MD5Sum/SHA1/SHA256/
  SHA512` checksums are *fields* of that single paragraph. A blank line anywhere
  in the body (e.g. before `MD5Sum:` or between sections) **ends the stanza**,
  detaching the checksums. apt then binds no strong hash and fails with:
  `W: No Hash entry in Release file …` + `E: … provides only weak security
  information.` Generate headers with **no leading `\n`**. `validate-release-file.sh`
  catches this.
- **apt 3.x treats MD5Sum and SHA1 as weak.** Always include **SHA256 and
  SHA512**. A repo with only MD5/SHA1 is rejected as "weak security information".
- **Serve a BINARY keyring** (`gpg --export > file`), not ASCII-armored
  (`gpg --armor --export`), for `signed-by=`. `file` should report
  "OpenPGP Public Key", not "PGP public key block".
- **Strip non-standard Packages fields.** `dpkg-scanpackages` can emit fields like
  `Architecture-Variant` that confuse some apt versions — `sed -i '/^Architecture-Variant:/d'`.
- **Verify without sudo by relocating apt's `Dir` tree.** Point `Dir` at a temp
  root and set `APT::Sandbox::User` to the current user (the `_apt` download
  sandbox otherwise can't write into a user temp dir). This is exactly what
  `verify-apt-repo.sh` does — a true `apt-get update` with zero system impact.
- **GitHub Pages CDN caches.** Different edges can briefly serve stale files.
  Cache-bust structural checks with `?cb=<timestamp>`. apt itself can't cache-bust;
  if a user still sees the old error, clear their lists:
  `sudo rm -f /var/lib/apt/lists/<host>_* && sudo apt update`.
- **`workflow_dispatch` uses the default-branch workflow definition.** Fixes to
  the publisher must reach the default branch before a dispatch regenerates the
  repo correctly.
- **`Date:` field** should be RFC1123 UTC: `date -u +"%a, %d %b %Y %H:%M:%S UTC"`.
- **install.sh under `curl | bash`:** `$0` is `/dev/fd/N` which `sudo` can't read.
  Re-fetch the script from its canonical URL before `exec sudo bash`.

## Files in this skill

- `scripts/verify-apt-repo.sh` — no-root, no-system-impact end-to-end apt check.
- `scripts/validate-release-file.sh` — static linter for the Release stanza bug + weak hashes.
- `scripts/gen-gpg-key.sh` — batch-generate the signing key (private + binary keyring).
- `templates/apt-repo.yml` — the corrected publisher workflow.
- `templates/install.sh` — the `curl | bash` installer.
- `templates/nfpm.yaml` — standalone `.deb` packaging for non-goreleaser projects.
- `templates/UNLICENSE` — the public-domain default license text (Phase 1.5).
