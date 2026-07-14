# Cookbook Nix Flake + Homebrew Tap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `homebrew-cookbook` as a single repo that distributes `gribe` as both a Nix flake package and a Homebrew formula, pinned to a prebuilt release binary, with automated version bumps.

**Architecture:** No compilation. Both channels fetch the prebuilt `gribe` binary from a transgribe GitHub release, install it, and generate shell completions by running the binary. The version/hash pin lives in `pkgs/gribe/source.json` (flake) and `Formula/gribe.rb` (brew). A dispatch-triggered GitHub Actions workflow recomputes hashes and opens a bump PR when transgribe publishes a release.

**Tech Stack:** Nix flakes (`nixpkgs` unstable), `stdenvNoCC` + `fetchurl` + `installShellFiles`, Homebrew Ruby DSL, GitHub Actions.

## Global Constraints

- **Platform:** `aarch64-darwin` only. Formula guards with `depends_on :macos` + `depends_on arch: :arm64`. Flake sets `meta.platforms = [ "aarch64-darwin" ]`.
- **License:** MIT (`lib.licenses.mit` / `license "MIT"`).
- **No code signing / notarization.** Rely on the ad-hoc signature `swift build` applies.
- **Source of the binary:** repo `jkeifer/transgribe`, release asset named `gribe`, URL `https://github.com/jkeifer/transgribe/releases/download/v<version>/gribe`.
- **Nix flakes only see git-tracked files** — always `git add` new/changed files before `nix build`/`nix flake` commands.
- **Initial pin (v0.1.0):** SRI `sha256-Lw0bCQSH368rsi3qi2+3HjbbyZEqL4pv38s9khzFrpM=` (flake), hex `2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93` (formula).
- **Working repo:** `_cookbook/` (the future `homebrew-cookbook`). All paths below are relative to `_cookbook/` unless the task says otherwise.

---

## File Structure

- `_cookbook/flake.nix` — flake outputs: `packages`, `apps`, `overlays` (aarch64-darwin).
- `_cookbook/pkgs/gribe/source.json` — machine-updatable pin: `repo`, `asset`, `version`, `sha256` (SRI).
- `_cookbook/pkgs/gribe/default.nix` — the `stdenvNoCC` derivation.
- `_cookbook/Formula/gribe.rb` — Homebrew binary formula.
- `_cookbook/.github/workflows/update.yml` — dispatch-triggered bumper (opens PR).
- `_cookbook/.gitignore` — ignore the `result` build symlink.
- `_cookbook/README.md` — consumption + maintenance docs.
- `transgribe/.github/workflows/release.yml` — add a "notify cookbook" dispatch step (separate repo).

---

## Task 1: Nix flake + gribe derivation

**Files:**
- Create: `_cookbook/pkgs/gribe/source.json`
- Create: `_cookbook/pkgs/gribe/default.nix`
- Create: `_cookbook/flake.nix`
- Create: `_cookbook/.gitignore`

**Interfaces:**
- Produces: flake outputs `packages.aarch64-darwin.gribe` / `.default`, `apps.aarch64-darwin.gribe` / `.default`, `overlays.default`. Derivation exposes `bin/gribe` plus completion files under `share/{bash-completion/completions,zsh/site-functions,fish/vendor_completions.d}`.
- `source.json` shape (consumed by `default.nix` and Task 3's updater): `{ "repo": string, "asset": string, "version": string, "sha256": SRI-string }`.

- [ ] **Step 1: Write `pkgs/gribe/source.json`**

```json
{
  "repo": "jkeifer/transgribe",
  "asset": "gribe",
  "version": "0.1.0",
  "sha256": "sha256-Lw0bCQSH368rsi3qi2+3HjbbyZEqL4pv38s9khzFrpM="
}
```

- [ ] **Step 2: Write `pkgs/gribe/default.nix`**

```nix
{ lib, stdenvNoCC, fetchurl, installShellFiles }:

let
  source = lib.importJSON ./source.json;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gribe";
  version = source.version;

  src = fetchurl {
    url = "https://github.com/${source.repo}/releases/download/v${finalAttrs.version}/${source.asset}";
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
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "gribe";
  };
})
```

- [ ] **Step 3: Write `flake.nix`**

```nix
{
  description = "jkeifer's cookbook: Nix flake + Homebrew tap for personal CLI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      gribe = pkgs.callPackage ./pkgs/gribe { };
    in
    {
      packages.${system} = {
        inherit gribe;
        default = gribe;
      };

      apps.${system} = {
        gribe = {
          type = "app";
          program = "${gribe}/bin/gribe";
        };
        default = self.apps.${system}.gribe;
      };

      overlays.default = final: _prev: {
        gribe = final.callPackage ./pkgs/gribe { };
      };
    };
}
```

- [ ] **Step 4: Write `.gitignore`**

```gitignore
result
result-*
```

- [ ] **Step 5: Stage files so the flake can see them, then build**

Flakes ignore untracked files, so stage first.

Run:
```bash
cd _cookbook
git add flake.nix pkgs/gribe/source.json pkgs/gribe/default.nix .gitignore
nix build .#gribe
```
Expected: build succeeds and creates a `result` symlink. (First run also writes `flake.lock`.)

- [ ] **Step 6: Verify the binary and completions**

Run:
```bash
cd _cookbook
./result/bin/gribe version
ls result/share/bash-completion/completions/gribe \
   result/share/zsh/site-functions/_gribe \
   result/share/fish/vendor_completions.d/gribe.fish
```
Expected: `gribe v0.1.0` (or `gribe v0.1.0-...`) printed, and all three completion files listed with no "No such file" error.

- [ ] **Step 7: Verify `nix run` and flake evaluation**

Run:
```bash
cd _cookbook
nix run .#gribe -- version
nix flake check
```
Expected: version printed; `nix flake check` completes without error.

- [ ] **Step 8: Commit**

```bash
cd _cookbook
git add flake.nix flake.lock pkgs/gribe/source.json pkgs/gribe/default.nix .gitignore
git commit -m "feat: add gribe nix flake package (prebuilt binary + completions)"
```

---

## Task 2: Homebrew formula

**Files:**
- Create: `_cookbook/Formula/gribe.rb`

**Interfaces:**
- Consumes: the same release URL/asset as Task 1.
- Produces: `Formula/gribe.rb` installable via `brew install jkeifer/cookbook/gribe` once published.

- [ ] **Step 1: Write `Formula/gribe.rb`**

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

Note: `generate_completions_from_executable(bin/"gribe", "--generate-completion-script")` uses the default `shells: [:bash, :zsh, :fish]` and default parameter format, running `gribe --generate-completion-script bash|zsh|fish` — matching gribe's CLI.

- [ ] **Step 2: Style-check the formula**

Run:
```bash
cd _cookbook
brew style Formula/gribe.rb
```
Expected: no offenses. If `brew style` reports fixable style issues, apply them and re-run until clean.

- [ ] **Step 3: Install-test the formula (best effort)**

Run:
```bash
cd _cookbook
brew install --formula ./Formula/gribe.rb && gribe version && brew uninstall gribe
```
Expected: installs, prints `gribe v0.1.0...`, uninstalls.

If this environment's Homebrew is nix-managed and blocks local installs, skip the install and instead confirm completion wiring by re-checking Task 1 Step 6 output (same binary, same `--generate-completion-script` flag). Record in the commit/PR that install-test was deferred to post-publish (`brew install jkeifer/cookbook/gribe`).

- [ ] **Step 4: Commit**

```bash
cd _cookbook
git add Formula/gribe.rb
git commit -m "feat: add gribe homebrew formula"
```

---

## Task 3: Cookbook auto-update workflow

**Files:**
- Create: `_cookbook/.github/workflows/update.yml`

**Interfaces:**
- Consumes: `repository_dispatch` (type `update-tool`) with `client_payload.{tool,tag}`, or `workflow_dispatch` inputs `{tool,tag}`. Reads `pkgs/<tool>/source.json` `.repo`/`.asset`.
- Produces: a PR editing `pkgs/<tool>/source.json` and `Formula/<tool>.rb`. Triggered by Task 4.

- [ ] **Step 1: Write `.github/workflows/update.yml`**

```yaml
name: Update tool

on:
  repository_dispatch:
    types: [update-tool]
  workflow_dispatch:
    inputs:
      tool:
        description: "Tool name (e.g. gribe)"
        required: true
      tag:
        description: "Release tag (e.g. v0.1.2)"
        required: true

permissions:
  contents: write
  pull-requests: write

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Resolve inputs
        id: vars
        run: |
          set -euo pipefail
          TOOL="${{ github.event.inputs.tool || github.event.client_payload.tool }}"
          TAG="${{ github.event.inputs.tag || github.event.client_payload.tag }}"
          if [ -z "$TOOL" ] || [ -z "$TAG" ]; then
            echo "tool and tag are required" >&2
            exit 1
          fi
          echo "tool=$TOOL" >> "$GITHUB_OUTPUT"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=${TAG#v}" >> "$GITHUB_OUTPUT"

      - name: Recompute hashes and rewrite pins
        env:
          TOOL: ${{ steps.vars.outputs.tool }}
          TAG: ${{ steps.vars.outputs.tag }}
          VERSION: ${{ steps.vars.outputs.version }}
        run: |
          set -euo pipefail
          SRC="pkgs/$TOOL/source.json"
          FORMULA="Formula/$TOOL.rb"
          REPO=$(jq -r '.repo' "$SRC")
          ASSET=$(jq -r '.asset' "$SRC")
          URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

          curl -fsSL -o "$ASSET" "$URL"
          HEX=$(shasum -a 256 "$ASSET" | awk '{print $1}')
          SRI="sha256-$(openssl dgst -sha256 -binary "$ASSET" | openssl base64 -A)"

          jq --arg v "$VERSION" --arg s "$SRI" '.version=$v | .sha256=$s' "$SRC" > "$SRC.tmp"
          mv "$SRC.tmp" "$SRC"

          sed -i -E \
            -e "s#/releases/download/[^/\"]*/$ASSET#/releases/download/$TAG/$ASSET#" \
            -e "s#^  version \"[^\"]+\"#  version \"$VERSION\"#" \
            -e "s#^  sha256 \"[0-9a-f]+\"#  sha256 \"$HEX\"#" \
            "$FORMULA"

          rm -f "$ASSET"

      - name: Open pull request
        uses: peter-evans/create-pull-request@v6
        with:
          branch: bump/${{ steps.vars.outputs.tool }}-${{ steps.vars.outputs.version }}
          title: "bump: ${{ steps.vars.outputs.tool }} ${{ steps.vars.outputs.version }}"
          commit-message: "bump: ${{ steps.vars.outputs.tool }} ${{ steps.vars.outputs.version }}"
          body: "Automated bump of ${{ steps.vars.outputs.tool }} to ${{ steps.vars.outputs.tag }}."
          add-paths: |
            pkgs/${{ steps.vars.outputs.tool }}/source.json
            Formula/${{ steps.vars.outputs.tool }}.rb
```

- [ ] **Step 2: Validate the workflow with actionlint**

Run:
```bash
cd _cookbook
nix run nixpkgs#actionlint -- .github/workflows/update.yml
```
Expected: no output (exit 0). Fix any reported issues and re-run until clean.

- [ ] **Step 3: Dry-run the rewrite logic locally**

This proves the hash/rewrite step edits both files correctly, without GitHub. It re-pins gribe to the *current* v0.1.0 (a no-op-value bump) in a scratch copy.

Run:
```bash
cd _cookbook
mkdir -p /private/tmp/claude-501/-Users-jkeifer-dev-transgribe/649f7355-8bb5-4195-ab80-9fec4885ff93/scratchpad/bump
cp -R pkgs Formula /private/tmp/claude-501/-Users-jkeifer-dev-transgribe/649f7355-8bb5-4195-ab80-9fec4885ff93/scratchpad/bump/
cd /private/tmp/claude-501/-Users-jkeifer-dev-transgribe/649f7355-8bb5-4195-ab80-9fec4885ff93/scratchpad/bump
TOOL=gribe TAG=v0.1.0 VERSION=0.1.0
SRC="pkgs/$TOOL/source.json"; FORMULA="Formula/$TOOL.rb"
REPO=$(jq -r '.repo' "$SRC"); ASSET=$(jq -r '.asset' "$SRC")
curl -fsSL -o "$ASSET" "https://github.com/$REPO/releases/download/$TAG/$ASSET"
HEX=$(shasum -a 256 "$ASSET" | awk '{print $1}')
SRI="sha256-$(openssl dgst -sha256 -binary "$ASSET" | openssl base64 -A)"
jq --arg v "$VERSION" --arg s "$SRI" '.version=$v | .sha256=$s' "$SRC" > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"
sed -i '' -E -e "s#/releases/download/[^/\"]*/$ASSET#/releases/download/$TAG/$ASSET#" -e "s#^  version \"[^\"]+\"#  version \"$VERSION\"#" -e "s#^  sha256 \"[0-9a-f]+\"#  sha256 \"$HEX\"#" "$FORMULA"
rm -f "$ASSET"
echo "SRI=$SRI HEX=$HEX"
cat "$SRC"; grep -E 'version|sha256|download' "$FORMULA"
```
Expected: `SRI` equals `sha256-Lw0bCQSH368rsi3qi2+3HjbbyZEqL4pv38s9khzFrpM=` and `HEX` equals `2f0d1b090487dfaf2bb22dea8b6fb71e36dbc9912a2f8a6fdfcb3d921cc5ae93`, and the printed formula lines show the same hex and the v0.1.0 URL. (Note: this local dry-run uses `sed -i ''` for macOS BSD sed; the workflow uses GNU `sed -i` on ubuntu-latest.)

- [ ] **Step 4: Commit**

```bash
cd _cookbook
git add .github/workflows/update.yml
git commit -m "ci: add dispatch-triggered tool version bumper"
```

---

## Task 4: transgribe release → dispatch to cookbook

**Files:**
- Modify: `transgribe/.github/workflows/release.yml` (separate repo — `/Users/jkeifer/dev/transgribe/.github/workflows/release.yml`)

**Interfaces:**
- Produces: a `repository_dispatch` (type `update-tool`) to `jkeifer/homebrew-cookbook` with `client_payload.{tool,tag}` — consumed by Task 3.
- Consumes: a repo secret `COOKBOOK_DISPATCH_TOKEN` (manual prerequisite — see Step 1).

- [ ] **Step 1: Create the dispatch token (manual, one-time)**

This cannot be automated. Ask the user to:
1. Create a fine-grained PAT (or GitHub App installation token) scoped to `jkeifer/homebrew-cookbook` with **Contents: read** and **Metadata: read** and permission to send repository dispatches (fine-grained PAT: repo access to `homebrew-cookbook`, `Contents: Read and write` is sufficient for dispatch; classic PAT: `repo` scope).
2. Add it to the **transgribe** repo as an Actions secret named `COOKBOOK_DISPATCH_TOKEN` (`gh secret set COOKBOOK_DISPATCH_TOKEN --repo jkeifer/transgribe`).

Record this in the PR description as a required setup step; the workflow step is inert until the secret exists.

- [ ] **Step 2: Add the notify step to `release.yml`**

Append this step to the `build` job in `/Users/jkeifer/dev/transgribe/.github/workflows/release.yml`, after the "Upload release asset" step:

```yaml
      - name: Notify cookbook
        if: ${{ github.event.release.tag_name != '' }}
        env:
          GH_TOKEN: ${{ secrets.COOKBOOK_DISPATCH_TOKEN }}
        run: |
          gh api repos/jkeifer/homebrew-cookbook/dispatches \
            -f event_type=update-tool \
            -f 'client_payload[tool]=gribe' \
            -f "client_payload[tag]=${{ github.event.release.tag_name }}"
```

- [ ] **Step 3: Validate the modified workflow**

Run:
```bash
cd /Users/jkeifer/dev/transgribe
nix run nixpkgs#actionlint -- .github/workflows/release.yml
```
Expected: no output (exit 0).

- [ ] **Step 4: Commit (in the transgribe repo, on a branch)**

```bash
cd /Users/jkeifer/dev/transgribe
git checkout -b ci/notify-cookbook-on-release
git add .github/workflows/release.yml
git commit -m "ci: notify homebrew-cookbook to bump gribe on release"
```

---

## Task 5: Cookbook README

**Files:**
- Create: `_cookbook/README.md`

**Interfaces:**
- Consumes: nothing. Documents Tasks 1–4 for end users and future maintainers.

- [ ] **Step 1: Write `README.md`**

```markdown
# homebrew-cookbook

A Nix flake **and** Homebrew tap distributing [jkeifer](https://github.com/jkeifer)'s
CLI tools. Versions are pinned here and decoupled from each tool's source — the tool
never knows its own version; this repo pins which released binary to serve.

Apple Silicon (`aarch64-darwin`) only.

## Tools

| Tool | Source | Description |
|------|--------|-------------|
| `gribe` | [transgribe](https://github.com/jkeifer/transgribe) | Transcribe audio locally on Apple Silicon |

## Install with Homebrew

```bash
brew tap jkeifer/cookbook
brew install gribe
```

## Install / run with Nix

```bash
# Run without installing
nix run github:jkeifer/homebrew-cookbook#gribe -- --help

# Add to a flake
inputs.cookbook.url = "github:jkeifer/homebrew-cookbook";
# then use inputs.cookbook.packages.aarch64-darwin.gribe,
# or inputs.cookbook.overlays.default for pkgs.gribe
```

Shell completions (bash/zsh/fish) are installed automatically by both channels.

### Browser downloads

If you download a tool's binary directly from its GitHub releases page (not via Nix
or Homebrew), macOS quarantines it. Clear it with:

```bash
xattr -d com.apple.quarantine ./gribe
```

Nix and Homebrew installs are not quarantined and need no such step.

## How versions are pinned

Each tool has `pkgs/<tool>/source.json` (`repo`, `asset`, `version`, `sha256`) read by
the flake, and a matching `Formula/<tool>.rb` for Homebrew.

Bumps are automated: when a tool publishes a GitHub release, its CI sends a
`repository_dispatch` to this repo, and `.github/workflows/update.yml` recomputes the
hashes and opens a PR. You can also bump manually from the Actions tab
("Update tool" → Run workflow → tool + tag).
```

- [ ] **Step 2: Commit**

```bash
cd _cookbook
git add README.md
git commit -m "docs: cookbook README (install, nix, brew, updates)"
```

---

## Post-implementation manual steps (not automatable here)

1. Create the GitHub repo `jkeifer/homebrew-cookbook` and push `_cookbook`'s `main`.
2. Create the `COOKBOOK_DISPATCH_TOKEN` secret in transgribe (Task 4 Step 1).
3. Open/merge the transgribe branch `ci/notify-cookbook-on-release`.
4. Verify end-to-end on the next transgribe release (or trigger "Update tool" manually), then confirm `brew install jkeifer/cookbook/gribe` works.

---

## Self-Review

- **Spec coverage:** layout (Task 1/2/3/5), prebuilt-binary derivation + completions (Task 1), one-repo flake+tap (Tasks 1–2, README), aarch64-only/MIT/no-signing (Global Constraints, applied in Tasks 1–2), formula (Task 2), dispatch auto-updater both sides (Tasks 3–4), xattr note (README). All spec sections map to a task.
- **Placeholders:** none — all files have complete contents; hashes are real values.
- **Type consistency:** `source.json` keys `repo`/`asset`/`version`/`sha256` are defined in Task 1 and consumed identically in Task 3; dispatch `event_type=update-tool` and `client_payload.{tool,tag}` in Task 4 match the `repository_dispatch` types/reads in Task 3.
