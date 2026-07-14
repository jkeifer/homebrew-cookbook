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
