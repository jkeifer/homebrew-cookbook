# Cookbook: Nix flake + Homebrew tap — design

**Date:** 2026-07-14
**Repo:** `jkeifer/homebrew-cookbook` (the `_cookbook` working dir, to be renamed/published under this name)
**First package:** `gribe` (from `jkeifer/transgribe`)

## Goal

A single centralized repository that distributes the author's CLI tools as both a
**Nix flake** and a **Homebrew tap**. Versions are pinned and owned by *this* repo,
decoupled from each tool's source. The tool's source has no concept of its own
version — the version is stamped at release time by the source repo's CI (git tag),
and this cookbook pins which released artifact to serve.

`gribe` is the first tool. The structure must make adding more tools, and bumping
versions, mechanical.

## Key decisions (resolved during brainstorming)

1. **Package the prebuilt release binary, not build from source.** Building the
   Swift/CoreML app hermetically in Nix is painful (SPM fetches deps over the
   network, blocked in the sandbox) and would stamp the version as `unknown`
   (`GitInfoPlugin` runs `git describe` against a `.git` that `fetchFromGitHub`
   doesn't include). transgribe's `release.yml` already uploads a `gribe` binary
   per tagged release with the version baked in — that is the ideal input.
2. **One repo, `homebrew-cookbook`**, serving as both flake and tap. The
   `homebrew-` prefix enables `brew tap jkeifer/cookbook`; the same repo still
   works as a flake (`nix run github:jkeifer/homebrew-cookbook#gribe`).
3. **No code signing / notarization.** Nix (`fetchurl` / store) and Homebrew do not
   set `com.apple.quarantine`, so the ad-hoc signature `swift build` already applies
   is sufficient — no Gatekeeper prompts through these channels. Developer ID +
   notarization would only benefit raw browser downloads from the releases page, and
   a bare Mach-O can't even be stapled (would need a `.pkg`). Documented as a
   README note (`xattr -d com.apple.quarantine`) for the browser-download case only.
4. **aarch64-darwin only.** The release asset is arm64-only.

## Repository layout

```
flake.nix                      # per-tool packages / apps / overlay
flake.lock
pkgs/
  gribe/
    default.nix                # the derivation (fetchurl + wrap + completions)
    source.json                # { "version": "0.1.0", "sha256": "sha256-..." }  ← machine-updatable pin
Formula/
  gribe.rb                     # Homebrew formula (binary)
.github/
  workflows/
    update.yml                 # dispatch-triggered version bumper; opens a PR
README.md
```

`pkgs/<tool>/source.json` is the single machine-editable pin the flake reads via
`builtins.fromJSON`. The Homebrew formula carries its own `version` + `sha256`
(Ruby, self-contained). The updater rewrites both in one PR.

## Nix flake

### Inputs
- `nixpkgs` (unstable or a pinned release — pick one, pinned in `flake.lock`).
- `flake-utils` optional; with a single system (`aarch64-darwin`) it can be inlined.

### Outputs (system: `aarch64-darwin`)
- `packages.aarch64-darwin.gribe` and `.default = gribe`
- `apps.aarch64-darwin.gribe` and `.default` → `nix run github:jkeifer/homebrew-cookbook#gribe`
- `overlays.default` — adds `gribe` to a nixpkgs instance for downstream consumers
- (No home-manager module for now — YAGNI. Add later if managed install is wanted.)

### `pkgs/gribe/default.nix`

`stdenvNoCC` derivation — no compilation:

```nix
{ lib, stdenvNoCC, fetchurl, installShellFiles }:

let source = lib.importJSON ./source.json;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gribe";
  version = source.version;

  src = fetchurl {
    url = "https://github.com/jkeifer/transgribe/releases/download/v${finalAttrs.version}/gribe";
    hash = source.sha256;
  };

  dontUnpack = true;
  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/gribe
    installShellCompletion --cmd gribe \
      --bash <($out/bin/gribe --generate-completion-script bash) \
      --zsh  <($out/bin/gribe --generate-completion-script zsh) \
      --fish <($out/bin/gribe --generate-completion-script fish)
    runHook postInstall
  '';

  meta = {
    description = "Transcribe audio locally on Apple Silicon";
    homepage = "https://github.com/jkeifer/transgribe";
    license = lib.licenses.mit;   # transgribe is MIT
    platforms = [ "aarch64-darwin" ];
    mainProgram = "gribe";
  };
})
```

- **Version** comes from `source.json` (cookbook-owned) — no git, no SPM, no CoreML build.
- **Completions** are generated at build time by running the fetched binary. This is
  safe: `swift-argument-parser`'s `--generate-completion-script` is pure, needs no
  models/network, and the arm64 binary runs on the `aarch64-darwin` builder. Guarded
  by `meta.platforms` so it is never attempted on Linux.

### `pkgs/gribe/source.json` (initial)

```json
{
  "version": "0.1.0",
  "sha256": "sha256-Lw0bCQSH368rsi3qi2+3HjbbyZEqL4pv38s9khzFrpM="
}
```

## Homebrew formula — `Formula/gribe.rb`

Binary formula pinned to the release URL:

```ruby
class Gribe < Formula
  desc "Transcribe audio locally on Apple Silicon"
  homepage "https://github.com/jkeifer/transgribe"
  url "https://github.com/jkeifer/transgribe/releases/download/v0.1.0/gribe"
  version "0.1.0"
  sha256 "2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "gribe"
    generate_completions_from_executable(bin/"gribe", "--generate-completion-script")
  end

  test do
    assert_match "gribe", shell_output("#{bin}/gribe version")
  end
end
```

- `generate_completions_from_executable(bin/"gribe", "--generate-completion-script")`
  with default `shells:` runs `gribe --generate-completion-script bash|zsh|fish` and
  installs each — matching gribe's CLI. (Verify the exact `shell_parameter_format`
  behavior against the current Homebrew API during implementation.)
- Homebrew downloads the raw binary (url ends in `/gribe`) to its cache; `bin.install`
  places it. Hex `sha256` for v0.1.0: `2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93`.

## Update automation

Keeps transgribe (source) ignorant of packaging while letting a release *trigger* a
cookbook bump. Two pieces:

### 1. transgribe `release.yml` — fire a dispatch (source side)

After the existing "upload release asset" step, add a step that notifies the cookbook:

```yaml
- name: Notify cookbook
  env:
    GH_TOKEN: ${{ secrets.COOKBOOK_DISPATCH_TOKEN }}   # can trigger workflows in homebrew-cookbook
  run: |
    gh api repos/jkeifer/homebrew-cookbook/dispatches \
      -f event_type=update-tool \
      -F client_payload[tool]=gribe \
      -F client_payload[tag]=${{ github.event.release.tag_name }}
```

Token: a fine-grained PAT (or GitHub App installation token) scoped to
`homebrew-cookbook` with **Actions: read/write** (dispatch) — stored as the
`COOKBOOK_DISPATCH_TOKEN` secret in transgribe. It only needs to *trigger*; hashing
stays in the cookbook.

### 2. cookbook `update.yml` — bump + PR (cookbook side)

```yaml
on:
  repository_dispatch:
    types: [update-tool]
  workflow_dispatch:
    inputs:
      tool: { description: tool name, required: true }
      tag:  { description: release tag (e.g. v0.1.2), required: true }
```

Steps (for `tool=gribe`, `tag=vX.Y.Z`):
1. Resolve `tool` / `tag` from `client_payload` or `inputs`.
2. Download `https://github.com/jkeifer/transgribe/releases/download/<tag>/gribe`.
3. Compute hashes: SRI (`nix hash convert`/`nix-prefetch-url`) for `source.json`,
   hex (`shasum -a 256`) for the formula.
4. Rewrite `pkgs/gribe/source.json` (`version`, `sha256`) and `Formula/gribe.rb`
   (`url`, `version`, `sha256`).
5. Open a PR with `peter-evans/create-pull-request` (review, or enable auto-merge).

Runner: `macos-*` for `nix`/`brew` availability, or `ubuntu` with `shasum` + Nix
install — either works since only hashing is needed.

## Concerns / notes

- **Completion generation runs the arm64 binary during the Nix build** — fine on an
  `aarch64-darwin` builder, impossible on Linux (guarded by `meta.platforms`).
- **arm64-only, ad-hoc-signed** release asset — runs from the Nix store / brew cellar
  without Gatekeeper prompts; x86_64 Macs unsupported; browser downloads need the
  `xattr` note.
- **License** — transgribe is MIT (`LICENSE`), reflected in `meta.license` and the
  formula `license`.
- The initial `gribe` v0.1.0 pin: SRI `sha256-Lw0bCQSH368rsi3qi2+3HjbbyZEqL4pv38s9khzFrpM=`
  (flake), hex `2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93` (formula).

## Out of scope (for now)

- Building any tool from source in Nix.
- home-manager / nix-darwin modules.
- x86_64-darwin or Linux support.
- Code signing / notarization / `.pkg` packaging.
- Additional tools beyond `gribe` (the layout supports them; add per-tool later).
