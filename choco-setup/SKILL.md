---
name: choco-setup
description: Set up a code repository end-to-end for Chocolatey (Windows) distribution — ensure a Windows build/release pipeline, produce versioned Windows zip artifacts with checksums, generate the Chocolatey package (nuspec + install/uninstall scripts + VERIFICATION/LICENSE), and a publisher workflow that packs and pushes to the Chocolatey Community Repository on every release — with local pack/install verification. Use when the user wants to distribute their app via Chocolatey, "choco install", a Windows package, a `.nupkg`, or a Chocolatey publisher pipeline.
---

# Chocolatey Distribution Setup

Take a repository from "builds a Windows binary" to "users run `choco install <pkg>`",
doing as much as possible automatically. The goal is **zero manual steps** for the
user where the tooling allows it (`gh` sets the API-key secret, downloads release
assets, dispatches the publisher; the skill generates the package, packs it, and
verifies a real local install). The one step the tooling genuinely cannot do for
the user is **obtain the Chocolatey account + API key** — that requires a human
signup at chocolatey.org. Make that the single copy-paste, and treat it as the
security-sensitive decision (see Operating principles).

Work on a dedicated branch and offer to merge at the end.

## Operating principles

- **Verify, don't assume.** Never tell the user "it works" until
  `scripts/verify-choco-package.ps1` passes: a real `choco pack` + local
  `choco install` from the produced `.nupkg`, the binary actually runs, and
  `choco uninstall` cleans up. We confirm what a real user's `choco install` sees.
- **Minimize intervention.** Prefer `gh` automation over hand instructions. Only
  fall back to manual when a capability is missing (no `gh` auth) or is inherently
  human (creating the chocolatey.org account and copying the API key).
- **Ask only on security.** If anything blocks, resolve it yourself from sensible
  defaults — *except* decisions that affect security (handling the API key, what
  binary gets downloaded/embedded, checksum policy). For those, stop and use
  `AskUserQuestion`. Never paste, echo, or commit the API key.
- **Surgical.** Add packaging/CI/license files; don't refactor the project.
- This skill runs natively on **Windows** (Chocolatey is Windows-only). `choco`
  and `gh` are expected on PATH. Use PowerShell for choco steps; `gh` works in
  either shell. If `choco` is absent, install it or note it as the one prerequisite.

---

## Phase 0 — Preflight: can this repo build & release a Windows binary?

This is the gate. Chocolatey ships Windows binaries; if the project can't produce
and publish one as a release asset, nothing downstream matters.

1. Detect language/build system: `go.mod` (Go), `Cargo.toml` (Rust),
   `package.json` (Node, e.g. pkg/nexe), `pyproject.toml` (Python, e.g. PyInstaller),
   `*.csproj`/`*.sln` (.NET), `CMakeLists.txt`/`Makefile` (C/C++), or a
   prebuilt-binary repo.
2. Determine whether a **Windows amd64** (and ideally **arm64**) binary is produced
   today, and whether CI publishes it as a **GitHub release asset**:
   - Go: try `GOOS=windows GOARCH=amd64 go build ./...`. Note CGO — if
     `CGO_ENABLED` must be 1, cross-compiling needs a Windows C toolchain; flag it.
   - Rust: `cargo build --release --target x86_64-pc-windows-msvc` (add the target).
   - .NET: `dotnet publish -r win-x64` (consider `--self-contained`).
   - Inspect `.github/workflows/*` for an existing release pipeline. **goreleaser**
     is the happy path for Go and already emits Windows `.zip` archives +
     `checksums.txt` — confirm the `archives:` block has a `format_overrides` of
     `[zip]` for `goos: windows` and a `checksum:` block. (derpy's `.goreleaser.yml`
     is the reference shape.)
3. **If there is NO Windows build/release workflow:** set up the minimal one before
   packaging. Use `AskUserQuestion` only if the build approach is ambiguous or
   security-relevant; for Go this is usually adding `windows` to goreleaser's
   `goos` (or a tiny `release.yml`). Do not proceed to packaging until a tagged
   release would produce **`<pkg>_<version>_windows_<arch>.zip`** assets plus a
   **`checksums.txt`** asset.

State what you found (language, arches, whether a Windows release artifact is
produced + how it's published) before continuing.

---

## Phase 1 — Branch

1. Infer the branch naming convention: inspect `git branch -a`, recent merge
   commits, and any `CONTRIBUTING`/`docs`. Common patterns: `feature/<x>`,
   `feat/<x>`, `<user>/<x>`.
2. Create and switch: default `feature/choco-setup` (adapt to the detected pattern).
3. If the working tree is dirty, note it; branch from the current HEAD.

---

## Phase 2 — Release artifacts (zip + checksums)

Chocolatey's install script downloads the Windows zip from the GitHub release and
verifies its SHA256 against `checksums.txt`. The publisher needs **stable,
predictable asset names**:

- Archive name: `<pkg>_<version>_windows_<arch>.zip` (e.g.
  `derpy_1.0.1_windows_amd64.zip`, `..._arm64.zip`).
- A `checksums.txt` asset listing the SHA256 of each archive.

Pick the path that fits the project:

- **Go + goreleaser (recommended):** ensure `builds.goos` includes `windows`,
  `archives` has `format_overrides: [{goos: windows, formats: [zip]}]`, the
  `name_template` produces `{{.ProjectName}}_{{.Version}}_{{.Os}}_{{.Arch}}`, and a
  `checksum:` block emits `checksums.txt`. The existing `release.yml` runs
  goreleaser on tag push.
- **Rust:** build each target, zip the `.exe`, and emit a checksums file in CI
  (e.g. a `windows.yml` job that uploads both assets to the release).
- **.NET / others:** publish the Windows binary, `Compress-Archive` to the required
  name, compute SHA256, and upload both as release assets.

Confirm: after a (test) release, `gh release view <tag> --json assets` lists
`<pkg>_<version>_windows_<arch>.zip` for every arch **and** `checksums.txt`.

---

## Phase 3 — License (UNLICENSE by default)

Chocolatey packaging references a license URL, and the Community Repository's
moderation expects a license to be discoverable.

1. If the repo already has a `LICENSE`/`LICENSE.txt`/`COPYING`, use it; read its
   SPDX type and reuse it in the nuspec.
2. **If no license file exists, add UNLICENSE** (public domain) — copy
   `templates/UNLICENSE` → repo-root `LICENSE`. Do not ask; this is the specified
   default. Mention it so the user can override.
3. The nuspec's `<licenseUrl>` should point at the served file
   (`https://github.com/<owner>/<repo>/blob/<default-branch>/LICENSE`), and the
   package `tools\LICENSE.txt` (Phase 5) holds the same text for the moderation
   bots.

---

## Phase 4 — Chocolatey account + API key (the one human step; security-gated)

Pushing to the Community Repository requires an API key tied to a chocolatey.org
account. The skill **cannot** create the account or read the key for the user.

1. Check whether it's already wired: `gh secret list` for `CHOCOLATEY_API_KEY`. If
   present, skip to Phase 5.
2. If not, this is a **security decision** — use `AskUserQuestion` to confirm how
   to proceed, offering: (a) the user pastes a key they already have, (b) the user
   creates an account at https://community.chocolatey.org/ → Account → API Keys and
   pastes the key, or (c) defer publishing (set everything up, skip the live push).
3. When the user provides the key, set it as the repo secret **without it ever
   touching the shell history or a file**:
   ```bash
   gh secret set CHOCOLATEY_API_KEY --app actions   # then paste when prompted
   ```
   (Prefer the interactive prompt — `gh` reads stdin so the key isn't an argv
   value. Never `echo "$KEY" | gh ...` into a logged command, never write the key
   to disk, never commit it.)
4. If `gh` lacks permission to set secrets, fall back to one instruction: "add a
   repo secret named `CHOCOLATEY_API_KEY` under Settings → Secrets and variables →
   Actions". Do not store the value yourself.

---

## Phase 5 — Chocolatey package files

Create a `chocolatey/` directory with these files (templates provided):

1. `chocolatey/<pkg>.nuspec` ← `templates/package.nuspec`. Replace placeholders:
   `__PKG__ __TITLE__ __AUTHORS__ __OWNER__ __REPO__ __DEFAULT_BRANCH__ __SUMMARY__
   __DESC__ __TAGS__`. Keep `id` lowercase; version is a placeholder the publisher
   rewrites per release.
2. `chocolatey/tools/chocolateyInstall.ps1` ← `templates/chocolateyInstall.ps1`.
   Replace `__PKG__ __OWNER__ __REPO__`. It selects the amd64/arm64 zip by
   `$env:PROCESSOR_ARCHITECTURE` and verifies the SHA256 checksum on download.
3. `chocolatey/tools/chocolateyUninstall.ps1` ← `templates/chocolateyUninstall.ps1`
   (removes the auto-created shim). Replace `__PKG__`.
4. `chocolatey/tools/VERIFICATION.txt` ← `templates/VERIFICATION.txt`. Required by
   moderation for downloaded binaries — explains provenance and how to verify the
   checksum against the GitHub release. Replace `__PKG__ __OWNER__ __REPO__`.
5. `chocolatey/tools/LICENSE.txt` ← the project `LICENSE` (UNLICENSE text from
   Phase 3). Moderation requires a license file in the package when it ships/
   downloads a binary.
6. Commit these on the feature branch.

> **Checksums in `chocolateyInstall.ps1` are required.** The Community Repository
> rejects downloaded binaries without a SHA256. The publisher (Phase 6) fills the
> real checksums from `checksums.txt` at release time — the committed file just
> needs valid placeholders the publisher's `sed`/`-replace` can target.

---

## Phase 6 — Publisher workflow

1. Copy `templates/chocolatey-publish.yml` → `.github/workflows/chocolatey-publish.yml`
   and replace `__PKG__`. It triggers on `release: published` (and `workflow_dispatch`
   with a `tag` input), downloads `checksums.txt`, rewrites the nuspec version +
   the install-script URLs and checksums for that release, `choco pack`s, and
   `choco push`es with `CHOCOLATEY_API_KEY`.
2. Confirm the asset-name patterns it greps for match what Phase 2 actually
   produces (`<pkg>_<version>_windows_amd64.zip` / `_arm64.zip`).
3. Commit on the feature branch.

> **`workflow_dispatch` runs the workflow definition from the DEFAULT branch.** If
> `chocolatey-publish.yml` is only on the feature branch, merge first (Phase 9) or
> push the workflow to the default branch before dispatching. Usually: merge, then
> dispatch.

---

## Phase 7 — Verify (hard gate — must pass before claiming success)

Run on Windows with `choco` available. This is a real pack + install, no live
push:

```powershell
pwsh -File scripts/verify-choco-package.ps1 -PackageDir chocolatey -Id <pkg>
```

The script:
1. `choco pack` the nuspec → a `.nupkg` (fails loudly on nuspec/script errors).
2. `choco install <pkg> -s "<dir-with-nupkg>;chocolatey" -y` — a real install that
   downloads the release zip and **enforces the checksum**.
3. Runs the installed shim (`<pkg> --version` or `<pkg> version`) to prove the
   binary works.
4. `choco uninstall <pkg> -y` to clean up; reports `PASS:` only if every step
   succeeded.

If the install step needs a real release to download from, run Phase 8's release
first (or point the script at a published tag). Only after `PASS:` do you report
success.

---

## Phase 8 — First publish + moderation

The publisher needs a release whose assets include the Windows zips + `checksums.txt`.

- If a suitable release already exists (assets present), use its tag.
- Otherwise cut one: bump version, `git tag vX.Y.Z && git push origin vX.Y.Z`, let
  the release workflow build and upload assets. Confirm with
  `gh release view <tag> --json assets`.

Trigger the publisher (it also runs automatically on `release: published`):
```bash
gh workflow run "Chocolatey Publish" -f tag=<tag>
gh run watch <run-id> --exit-status
```

> **Community moderation is asynchronous.** A brand-new package id goes through
> automated validation **and human moderation** before it's installable by the
> public — this can take hours to days and is outside the repo's control. Tell the
> user: a successful `choco push` means "submitted", not "live". Track status on
> the package page at `https://community.chocolatey.org/packages/<pkg>`. (For an
> internal/self-hosted feed, set the publisher's `--source` to that feed instead;
> no moderation.)

---

## Phase 9 — Merge

1. Summarize what changed (files added, license chosen, API-key secret set or
   deferred, verify results, publish/moderation status).
2. Offer to merge `feature/choco-setup` → default branch, matching the user's
   workflow (`gh pr create`, or fast-forward merge). Remember: the publisher
   becomes auto-triggered + dispatchable from the default branch only after merge.

---

## Critical knowledge (the gotchas that cost real debugging time)

- **A successful `choco push` ≠ installable.** First-time package ids hit automated
  validation + human moderation on the Community Repository. Don't report "users
  can `choco install` now" until the package page shows it approved/listed.
- **Downloaded binaries MUST carry a SHA256 checksum** in `chocolateyInstall.ps1`
  and a **`VERIFICATION.txt`** + **`LICENSE.txt`** in `tools\`. Moderation rejects
  packages that download an external binary without these. The checksum must match
  the release zip exactly — the publisher copies it from goreleaser's
  `checksums.txt`.
- **Package `id` must be lowercase**; `<version>` must be strict SemVer (no leading
  `v`). The publisher strips the tag's `v` (`VERSION="${TAG#v}"`).
- **Prefer `$env:PROCESSOR_ARCHITECTURE` for arch detection**, not the deprecated
  `Get-WmiObject Win32_Processor` (slow, WMI-dependent, broken under some sandboxes).
  `ARM64` → arm64 zip; `AMD64` → amd64 zip.
- **`requireLicenseAcceptance` should be `false`** unless the license genuinely
  requires interactive acceptance — `true` breaks unattended `choco install -y`.
- **`Install-ChocolateyZipPackage` auto-creates shims** for `.exe` files in the
  unzip location — that's how `<pkg>` lands on PATH. The matching
  `chocolateyUninstall.ps1` should remove them (or rely on Chocolatey's auto-shim
  cleanup) so uninstall is clean.
- **`workflow_dispatch` uses the default-branch workflow definition.** Fixes to the
  publisher must reach the default branch before a dispatch republishes correctly.
- **Never echo or persist the API key.** Set it via `gh secret set` with an
  interactive prompt; in CI it's `${{ secrets.CHOCOLATEY_API_KEY }}`. It must never
  appear in argv, logs, files, or commits.
- **`choco pack`/`choco install` need elevation/Windows.** Verification is a
  Windows-only step; there is no cross-platform shortcut. Run it natively.

## Files in this skill

- `scripts/verify-choco-package.ps1` — real local pack + install + run + uninstall gate.
- `templates/chocolatey-publish.yml` — the publisher workflow (checksum-aware, push on release).
- `templates/package.nuspec` — generalized nuspec with placeholders.
- `templates/chocolateyInstall.ps1` — arch-aware, checksum-verifying zip installer.
- `templates/chocolateyUninstall.ps1` — shim cleanup on uninstall.
- `templates/VERIFICATION.txt` — provenance/checksum statement required by moderation.
- `templates/UNLICENSE` — the public-domain default license text.
